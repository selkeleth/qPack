#!/bin/bash

CONFIG_FILE="$HOME/.qPack_config"
scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${scriptDir}/qDev.sh"
source "${scriptDir}/qTemplates.sh"
source "${scriptDir}/qPackInfo.sh"

set -e

# Function to read a specific key from a section
# Usage
#savePath=$(get_config_value "Local" "savePath")
get_config_value() {
    local section=$1
    local key=$2
    if [[ -f "$CONFIG_FILE" ]]; then
        # output the value, removing any whitespace
        awk -F '=' '/\['"$section"'\]/{a=1} a==1&&$1~/'"$key"'/{print $2; exit}' "$CONFIG_FILE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
    else
        echo "qWrapper: No config file found at $CONFIG_FILE. Please run qPackConfig." 1>&2
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
    local piece_length

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

    # Create the torrent
    mktorrent -a "$announceUrl" -p -s "Unwalled" -o "$outputFile" "$target" > /dev/null
   
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
    yearList="$2"
    local upTo="$3"
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

    if [[ -z "$upTo" || ( "$current_year" != "$minYear" && "$current_year" != "$maxYear" ) ]]; then
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
    eval set -- "$jobString"

    local job="$1"

    # Parse job-dependent arguments
    case "$job" in
        "-t1" | "-ta" )
            local y1="$2"
            local y2="$3"
            if [[ -z "$y1" || -z "$y2" ]]; then
                if [[ -z "$y2" ]]; then
                    yearList="$y1"
                else # do all the years
                    yearList="${!year_filecount[@]}"
                fi
            elif [[ ! -z "$(seq $y1 $y2)" ]]; then 
                yearList="$(seq $y1 $y2 | tr "\n" " ")"
            elif [[ ! -z "$(seq $y2 $y1)" ]]; then
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
        *)
            echo qWrapper.sh: "$job" not implemented. 1>&2
            ;;
    esac

    # Execute job
    case "$job" in
        "-t1" | "-ta" )
            dirName=""
            if [[ -f "$target_directory/cover.jpg" ]]; then
                cover="cover.jpg"
            elif [[ -f "$target_directory/cover.png" ]]; then
                cover="cover.png"
            else
                cover=""
            fi
            if [[ ! -z "$cover" ]]; then # make a thumb in the thumb / save path
                if [[ -z "$thumbPath" ]]; then
                    convert "$target_directory/$cover" -resize 600x600 "$savePath/cover-$(basename "$(pwd)")-1-1.jpg"
                else
                    convert "$target_directory/$cover" -resize 600x600 "$thumbPath/cover-$(basename "$(pwd)")-1-1.jpg"
                fi
            fi
            if [[ $job == "-ta" ]]; then
                current_year=$(date +%Y)
                for year in ${yearList}; do
                    populate_bitString "$target_directory" "$year"
                    if [[ "$year" == "$current_year" ]]; then
                        format_dirName "$target_directory" "$current_year" "YTD"
                    else
                        format_dirName "$target_directory" "$year"
                    fi
                    echo mkdir "$torrentDataPath/$dirName"
                    if [[ ! -z "$cover" ]]; then 
                        if [[ -z "$thumbPath" ]]; then
                            convert "$target_directory/$cover" -resize 600x600 "$savePath/cover-$(basename "$(pwd)")-1-1.jpg"
                        else
                            convert "$target_directory/$cover" -resize 600x600 "$thumbPath/cover-$(basename "$(pwd)")-1-1.jpg"
                        fi
                    fi
                    if [[ $lnOrCp == "1" ]]; then
                        if [[ -z "$cover" ]]; then
                            echo ln "$target_directory/$cover" "$torrentDataPath/$dirName/"
                        fi
                        echo ln "$target_directory/*[${year}*" "$torrentDataPath/$dirName/"
                    else
                        if [[ -z "$cover" ]]; then
                            echo cp "$target_directory/$cover" "$torrentDataPath/$dirName/"
                        fi
                        echo cp "$target_directory/*[${year}*" "$torrentDataPath/$dirName/"
                    fi
                done
            else
                echo "*** Packing up"
                populate_bitString "$target_directory" "$yearList"
                format_dirName "$target_directory" "$yearList"
                mkdir "$torrentDataPath/$dirName"
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
                #echo "*** Making torrent for $dirName"
                #create_torrent "$torrentDataPath/$dirName"
                #echo "*** Sending $dirName data to seedbox"
                #sync_to "$torrentDataPath/$dirName"
                #if [[ $seed_watchPath != "" ]]; then # sync the .torrent file to the user's seedbox's client's watch directory
                #    echo "*** Sending torrent file to seedbox"
                #    sync_to "$file" "1"
                #fi

                target="$(realpath "$torrentDataPath"/"$dirName")"
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
                    sync_to "$torrentDataPath/$dirName" > /dev/tty
                    if [[ $seed_watchPath != "" ]]; then # sync the .torrent file to the user's seedbox's client's watch directory
                        echo "* Adding to seedbox torrent client via watch path"
                        sync_to "$file" "1" > /dev/tty
                    fi
                fi
            fi
            ;;
        * )
            echo qWrapper.sh: Internal error processing "$job" in execute_job\(\) /devv/tty
            echo tell Q to stop padding his uploads and make this work! /dev/tty
            ;;
    esac
}