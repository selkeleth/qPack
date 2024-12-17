#!/bin/bash

CONFIG_FILE="$HOME/.qPack_config"
#scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${scriptDir}/resources/qDev.sh"
source "${scriptDir}/resources/qTemplates.sh"
source "${scriptDir}/resources/qPackInfo.sh"

set -e

# Function to read a specific key from a section
# Usage
#savePath=$(get_config_value "Local" "savePath")
get_config_value() {
    local section=$1
    local key=$2
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "qWrapper: No config file found at $CONFIG_FILE. Running qPackConfig." 1>&2
        local qPackConfigSh="$(dirname "$(realpath "$0")")"/qPackConfig.sh
        $qPackConfigSh
    fi
    if [[ -f "$CONFIG_FILE" ]]; then
        # output the value, removing any whitespace
        awk -F '=' '/\['"$section"'\]/{a=1} a==1&&$1~/'"$key"'/{print $2; exit}' "$CONFIG_FILE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
    else
        echo "qWrapper: No config file found at $CONFIG_FILE. Please complete qPackConfig." 1>&2
        exit 1
    fi
}

# Function to get the error log path
# Usage
init_error_log() {
    local logName="$1"
    local yn
    errorLogPath=$(get_config_value "Local" "errorLogPath")
    if [[ -z "$errorLogPath" ]]; then
        echo "qWrapper: Error log path not set. Please run qPackConfig." 1>&2
        exit 1
    fi
    errorLogPath="${errorLogPath%/}"
    if [[ ! -d "${errorLogPath}" ]]; then
        echo "qWrapper: Error log path is not a directory: ${errorLogPath}" 1>&2
        exit 1
    fi
    if [[ -z "$logName" ]]; then
        echo "qWrapper: init_error_log()- called without a log name" 1>&2
        exit 1
    else
        errorLog="${errorLogPath}/error-${logName}.log"
    fi
    if [[ -f "$errorLog" ]]; then
        echo "${errorLog} already exists. Would you like to view it?"
        read -p "y/n: " yn
        if  [[ $yn  ==  [Yy]  ]]; then
            less "$errorLog"
        fi
        echo "Would you like to remove it? Errors will be appended to the existing log if you choose no."
        read -p "y/n: " yn
        if [[ $yn == [Yy] ]]; then
            rm "$errorLog"
        fi
    fi

    echo $errorLog
}

# Create a torrent with the given target, target and title, or target, title, and announceUrl
#
create_torrent() {
    local target="$1"
    local outputTitle="$2" # not implemented
    local announceUrl="$3"
    # Falling back to config instead of requiring the announce makes it 
    # friendlier for standalone usage if a user sources qWrapper.sh for 
    # use on the CLI
    if [[ -z "$announceUrl" ]]; then
        announceUrl=$(get_config_value "Tracker" "announceUrl")
    fi
    # Optionally set a custom torrent title
    if [[ ! -z "$outputTitle" ]]; then
        titleOption="-n '$outputTitle'"
    fi
    local title_flag=""

    if [[ -z "$savePath" ]]; then
        savePath=$(get_config_value "Local" "savePath")
    fi

    # Check for required parameters
    if [[ -z "$target" || -z "$announceUrl" ]]; then
        echo "Usage: create_torrent <target> [ [outputTitle] | [ outputTitle announceUrl ]"
        echo 
        echo "<target> is the required file or directory target"
        echo "You may optionally provide either a title or a title and announceUrl"
        echo "qPack will attempt"
        exit 1
    fi

    # Check if the target exists
    if [[ ! -e "$target" ]]; then
        echo "Error: Target '$target' does not exist." 1>&2
        exit 1
    fi

    if [[ -d "$target" ]]; then
        outputFile="$(get_ntfs_safe "$(basename "$target").torrent")"
    else
        outputFile="$(get_ntfs_safe "${target%.mp3}.torrent")"
    fi

    if [[ ! -z "$savePath" ]]; then
        outputFile="$savePath/$outputFile"
    fi

    # Check if the output file already exists
    if [[ -e "$outputFile" ]]; then
        echo "Error: Output file '$outputFile' already exists." 1>&2
        exit 1
    fi

    local piece_length=$(get_piece_length "$target")

    # Create the torrent
    mktorrent -l "$piece_length" -a "$announceUrl" -p -s "Unwalled" -o "$outputFile" "$target" > /dev/null
   
    if [[ $? -eq 0 ]]; then
        echo "$outputFile"
    else
        echo "Failed to create torrent." 1>&2
        exit $?
    fi
}

# Sync to remote seedbox
# Usage: sync_to <target> [remote_dir]
#
# "1" may be given as remote_dir to indicate that the.torrent should be placed
#    in the seedbox client's torrent watch directory.
#
sync_to() {
    target="$1"
    if [[ -n "$2" ]]; then # either placing a .torrent using flag "1" or using a specified path
        if [[ "$2" == "1" ]]; then # send to seedbox client watch directory
            seedPath=$(get_config_value "Seedbox" "watchPath")
        else
            seedPath="$2"
        fi
    else # Garden variety default directory
        seedPath=$(get_config_value "Seedbox" "seedPath")
    fi
    seedUser=$(get_config_value "Seedbox" "seedUser")
    seedServer=$(get_config_value "Seedbox" "seedServer")

    if [[ -z $seedPath ]]; then
        echo "sync_to(): Unable to set seedPath. Please run qPackConfig."
        exit 1
    fi

    rsync -azh --info=progress2 "$target" $seedUser@$seedServer:$seedPath
}

# Form a directory name from a provided source and the following year argument(s)
# Requires arrays to be set by the calling scope
format_dirName() {
    local target_directory="$1"
    local upTo="$2"
    yearList="$3"

    if [[ -z "$yearList" ]]; then # do all the years
        yearList="${!year_filecount[@]}"
    fi
    local name="$(basename "$target_directory")"
    if [[ -n $podcastName ]]; then
        if [[ -z "$podcastName" ]]; then
            name=$podcastName
        fi
    fi

    local sortedYearList=($(echo $yearList | tr " " "\n" | sort -n))
    local yearCount=${#sortedYearList[@]}
    local lastYearIndex=$((yearCount-1))
    local minYear=${sortedYearList[0]}
    local maxYear=${sortedYearList[$lastYearIndex]}

    if [[ "$maxYear" == "$minYear" ]]; then
        yearString="$minYear"
    else
        yearString="${minYear}-${maxYear}"
    fi

    if [[ -z $podcastName || -z $yearString || -z $bitString ]]; then
        echo "Error: Missing info among podcastname $podcastName; yearString $yearString; bitString $bitString" > /dev/tty
        exit 1
    fi
    
    if [[ $percentage -lt 70 ]]; then
        bitString="MIX kbps"
    fi

    current_year=$(date +%Y)

    # Checks that $upTo is not an empty string or set to "0"
    if [[ -z "$upTo" || "$upTo" == "0" ]]; then
        local name="${podcastName} [${yearString}_MP3-${bitString}]"
    else # we should label the directory/torrent that it's the current year up to the latest episode's mm.dd
        # Extract dates in YYYY.MM.DD format
        dates=($(find "$target_directory" -type f -name "*\[$current_year*.mp3" | grep -oP '\d{4}\.\d{2}\.\d{2}' | sort))

        # Get the latest date in the list and format it to MM-DD
        latest_date=${dates[-1]}
        month=$(echo "$latest_date" | cut -d '.' -f 2)  # Extract MM
        day=$(echo "$latest_date" | cut -d '.' -f 3)    # Extract DD
        upTo="${month}.${day}"                          # Combine to MM-DD

        if [[ $upTo == "." ]]; then
            local name="${podcastName} [${yearString} (partial)_MP3-${bitString}]"
        else
            local name="${podcastName} [${yearString} up to ${upTo}_MP3-${bitString}]"
        fi
    fi
    
    dirName=$name
}

# Usage: qPackIt <target_directory> <torrentDataPath> <lnOrCp> <upTo> <yearList>
# 
# upTo, I'm ashamed to say, is used as a flag for whether to pack the torrent
#   using the upTo format. Someday it should be a template for the upTo! For now
#   set it to zero (or blank) to prevent YTD "up to" date and anything else 
#   for a created torrent of the current year to list the release date of the 
#   most recent episode in the directory targeted.
#
qPackIt() {
    local target_directory="$1"
    if [[ -z "$torrentDataPath" ]]; then
        torrentDataPath="$2"
    fi
    if [[ -z "$lnOrCp" ]]; then
        lnOrCp="$3"
    fi
    upTo="$4"
    yearList="$5"
    if [[ -z "$yearList" ]]; then # no parameter = do all the years
        yearList="${!year_filecount[@]}"
    else # validate it
        for y in $yearList; do # check every year
            if [[ -z $(find "$target_directory" -type f -name "*[$y*") ]]; then # if it's not in the directory
                yearList="$(echo $yearList | sed -E "s/$y//")" # it shouldn't be in the list
            fi
        done
    fi
    local y1
    local y2
    
    # Set up the target directory
    if [[ ! -d "$target_directory" ]]; then
        echo "Directory target for source data does not exist: $target_directory"
        exit 1
    fi

    # Set up the torrentDataPath
    if [[ ! -d "$torrentDataPath" ]]; then
        echo "Torrent data path does not exist: $torrentDataPath"
        exit 1
    fi

    echo "* qPack year(s) : $yearList"
    populate_bitString "$target_directory" "$yearList"
    format_dirName "$target_directory" "0" "$yearList"
    mkdir "$torrentDataPath/$dirName"
    if [[ ! -d "$torrentDataPath/$dirName" ]]; then
        echo "Failed to create directory: $torrentDataPath/$dirName" 1>&2
        exit 1
    fi
    if [[ -f "$target_directory/cover.jpg" ]]; then
        cover="cover.jpg"
    elif [[ -f "$target_directory/cover.png" ]]; then
        cover="cover.png"
    else
        cover=""
    fi

    if [[ $lnOrCp == "1" ]]; then
        if [[ ! -z "$cover" ]]; then 
            ln "$target_directory/$cover" "$torrentDataPath/$dirName/"
        fi
        for year in $yearList; do
            ln "$target_directory"/*[${year}* "$torrentDataPath/$dirName/"
        done
    else
        if [[ ! -z "$cover" ]]; then 
            cp "$target_directory/$cover" "$torrentDataPath/$dirName/"
        fi
        for year in $yearList; do
            cp "$target_directory"/*[${year}* "$torrentDataPath/$dirName/"
        done
    fi

    target="$(realpath "$torrentDataPath"/"$dirName")"
    echo "* Creating torrent"
    file=$(create_torrent "$target" "$dirName")
    file=$(echo $file | tail -n 1)
    # Check if the function succeeded and use the result
    if [[ $? -eq 0 ]]; then
        echo "* Saved $file"
        if [[ $local_watchPath != "" ]]; then # save another copy to the local watch path
            cp "$file" "$local_watchPath"
            echo "* Added .torrent to local client via watch path"
        fi
    else
        echo "Error creating torrent." 1>&2
    fi
    if [[ $seedUser != ""  ]]; then # sync the torrent data to the user's seedbox
        echo "* Sending torrent data to seedbox"
        sync_to "$torrentDataPath/$dirName"
        if [[ $seed_watchPath != "" ]]; then # sync the .torrent file to the user's seedbox's client's watch directory
            echo "* Adding to seedbox torrent client via watch path"
            sync_to "$file" "1"
        fi
    fi

    echo "* Completed: $dirName"
}

# Execute a job given qPack parameters
# <target_directory> <JOB> [OPTIONS]
# JOBS:
# -t1 [y1] | [y1 y2]    : create 1 torrent for target_directory
#                           [y1] : for mp3's of year [y1]
#                           [y1] [y2] : for mp3's spanning between given years
# -ta [y1] | [y1 y2]    : create separate torrents by years
#                           The other difference from t1 is that, if the year
#                           is the current year, it will create a YTD "up to"
#                           torrent
# -o <pack_option>      : creates torrent(s) per option:
#                           1) One YTD torrent, one torrent for prior years
#                           2) One torrent for all years
#                           3) One YTD torrent, one torrent for each prior year

execute_job() {
    # Set parameter variables now because eval set to the jobString next
    local target_directory="$1"
    local jobString="$2"

    # parse jobString parameters
    jobString=$(echo "$jobString" | sed 's/[<>&|;\\]//g')
    eval set -- "$jobString"

    local job="$1"

    # Different jobs require different arguments to execute
    # The first step is to eval the jobString for its arguments and populate
    # the variables with the values.
    # The second step is to run the appropriate functions for the given job
    # using these parameters

    # This case statement is step 1 - set the appropriate parameters for a
    # given job into sensible variable names. 
    case "$job" in
        "-t1" | "-ta" )
            local y1="$2"
            local y2="$3"
            if [[ -z "$y1" || -z "$y2" ]]; then
                if [[ -z "$y2" ]]; then # there's no y2, do y1 only
                    yearList="$y1"
                else # do all the years
                    yearList="${!year_filecount[@]}"
                fi
            elif [[ ! -z "$(seq $y1 $y2)" ]]; then # y2 > y1, they're valid numbers, etc
                yearList="$(seq $y1 $y2 | tr "\n" " ")"
            elif [[ ! -z "$(seq $y2 $y1)" ]]; then # the user put dates in "reverse" order
                yearList="$(echo "$(seq $y2 $y1)")"
            else
                echo qWrapper.sh: Internal error processing "$job" in execute_job\(\) "$y1" "$y2" 1>&2
                exit 1
            fi
            ;;
        "-o" )
            packOption="$2"
            ;;
        "-p" ) # Print options report
            "$scriptDir/printOptionsReport.sh" "$target_directory"
            ;;
        "--thumb" ) # make thumbnail for directory
            # Change if requested
            savePath="$2"
            thumbPath="$3"
            ;;
        *)
            echo qWrapper.sh: "$job" not implemented. 1>&2
            ;;
    esac
    

    # This is step 2, execution of the job itself using the parameters in
    # jobString that were just parsed into sensible variable names
    case "$job" in
        "--thumb" )
            thumbFile="$(make_thumb "$target_directory" "$savePath" "$thumbPath")"
            echo "* $thumbFile"
            ;;
        #  We'll  handle the t(orrent) "single" (1) and "(a)nnual" commands together
        "-t1" | "-ta" ) 
            dirName=""
            thumbFile="$(make_thumb "$target_directory" "$savePath" "$thumbPath")"
            echo "* Will pack years ${yearList}"
            if [[ $job == "-ta" ]]; then
                current_year="$(date +%Y)"
                for year in ${yearList}; do
                    echo "* Packing year $year"
                    if [[ "$year" == "$current_year" ]]; then
                        qPackIt "$target_directory" "$torrentDataPath" "$lnOrCp" "YTD" "$current_year"
                    else
                        qPackIt "$target_directory" "$torrentDataPath" "$lnOrCp" "0" "$year"
                    fi
                done
            else
                qPackIt "$target_directory" "$torrentDataPath" "$lnOrCp" "0" "$yearList"
            fi
            ;;
        "-o" )
# -o <pack_option>      : creates torrent(s) per option:
#                           1) One YTD torrent, one torrent for prior years
#                           2) One torrent for all years
#                           3) One YTD torrent, one torrent for each prior year
            dirName=""
            thumbFile="$(make_thumb "$target_directory" "$savePath" "$thumbPath")"
            current_year="$(date +%Y)"
            case "$packOption" in
                "1" )
                    # check if target directory has has current year and make YTD if so                    
                    if [[ ! -z "$(echo ${!year_filecount[@]} | grep "$current_year")" ]]; then
                        echo "* Creating YTD torrent"
                        qPackIt "$target_directory" "$torrentDataPath" "$lnOrCp" "YTD" "$current_year"
                    fi

                    yearList="$(echo ${!year_filecount[@]} | sed -E "s/$current_year//")"
                    echo "* Creating archive torrent for $yearList"
                    qPackIt "$target_directory" "$torrentDataPath" "$lnOrCp" "0" "$yearList"
                    ;;
                "2" )
                    # Make one torrent for all years - qPackIt <target_directory> <torrentDataPath> <lnOrCp>
                    qPackIt "$target_directory" "$torrentDataPath" "$lnOrCp" 
                    ;;
                "3" )
                    # Make one YTD torrent, one torrent for each prior year
                    # check if target directory has has current year and make YTD if so                    
                    if [[ ! -z "$(echo ${!year_filecount[@]} | grep "$current_year")" ]]; then
                        echo "* Creating YTD torrent"
                        qPackIt "$target_directory" "$torrentDataPath" "$lnOrCp" "YTD" "$current_year"
                    fi

                    for year in "$(echo ${!year_filecount[@]} | sed -E "s/$current_year//")"; do
                        echo "* Creating archive torrent for $year"
                        qPackIt "$target_directory" "$torrentDataPath" "$lnOrCp" "0" "$year"
                    done
                    ;;
                * )
                    echo "$packOption is unknown for -o"  >  /dev/tty
                    ;;
            esac
            ;;
        * )
            echo qWrapper.sh: Internal error processing "$job" in execute_job\(\) > /dev/tty
            ;;
    esac
}