#!/bin/bash

SECONDS=0
set -e

# These take more resources to populate than to make global
declare -g -A year_filecount
export year_filecount
declare -g -A year_filesize
export year_filesize
declare -g -A year_bitrate_counts
export year_bitrate_counts
declare -g -A bitrate_totals
export bitrate_totals
declare -g bitString
export bitString
declare -g bitPercentage
export bitPercentage
declare -g nextJob
export nextJob
declare -g scriptDir
export scriptDir

# vanilla array for job queue
declare -a jobQueue

# Function to display help message for running qPack.sh from the CLI
show_help() {
    cat << EOF

Usage: ${0##*/} [OPTIONS] [source directory]

Options:
    -n                 : Specify the podcast name (defaults to directory name)
    -h, --help         : Show this help message
EOF
}

# Function to display the help message once within qPack.sh
show_menu() {
    cat << EOF

Tools and basics-
rh              : Print a summary of the rename tool's options
r <options>     : Run the rename tool to format the filenames
thumb           : Save a thumbnail for the working directory
p               : Print a torrent options report for "o <#>"
cd [dir]        : Change the working directory to [dir] to optional [dir]
                    Will prompt with tab-completion if [dir] is not specified
q               : Quit
?               : Print this menu

Packing and torrenting- jobs will be placed in a queue until the queue is run
pq              : Print the queue
run             : Run the queue, packing list of torrents specified
o <#>           : Pack per option #
                    1) One YTD torrent, one torrent for prior years
                    2) One torrent for all years
                    3) One YTD torrent, one torrent for each prior year
t1 [y1] [y2]    : Pack one single torrent 
                    [for year(s) y1 [through y2]]
ta [y1] [y2]    : Pack a separate torrent for each year
                    [for year(s) y1 [through y2]]
                    This will create a "YTD" torrent for the current year.
                    YTD torrent directory and torrent title will have "up to
                    mm.dd" for the most recent episode of the current year.
EOF
}

# Function to resolve the full path of the script, regardless of whether it was
# invoked with a symlink and/or via $PATH
#
# Usage: scriptPath=$(resolve_init_script_path $0)
resolve_init_script_path() {
    local script="$1"
    local script_dir

    # If invoked without a path component, search the PATH
    if [[ "$script" != */* ]]; then
        # Use the command 'which' to find the full path in $PATH
        script=$(which "$script") || return 1
    fi

    # Continue resolving to ensure we follow any symlinks
    while [ -h "$script" ]; do
        script_dir=$(dirname -- "$script")
        # Use readlink to read the target of the symlink
        script=$(readlink -- "$script")
        
        # If script was a relative symlink, resolve it relative to the directory of the symlink
        [[ "$script" != /* ]] && script="$script_dir/$script"
    done

    # Return the absolute path
    script_dir=$(dirname -- "$script")
    script=$(cd -P -- "$script_dir" && pwd -P)/$(basename -- "$script")

    echo "$script_dir"
}

initSourceDir() {
    # Begin interactive mode as needed
    if [[ -z "$sourceDir" ]]; then # we must get it populated interactively
        sourceDir="$(read_relative_path "Data source directory" "$mediaPath" "1" | tail -n 1)"
    fi

    # If the podcast name wasn't specified by an argument
    #   pick a default name from the source directory
    if [[ -z "$podcastName" ]]; then
        podcastName="$(get_ntfs_safe "$(basename "$sourceDir")")"
    fi

    if [[ ! -n $errorLog ]]; then
        echo "* Setting error log"
        init_error_log "$podcastName"
        errorLog="$(echo $errorLog | tail -n 1)"
    fi
    if [[ -z $errorLog ]]; then
        echo "Error initializing error log for $podcastName."
        exit 1
    fi

    filecount="$(ls "$sourceDir"/*mp3 | wc -l)"
    if [[ $filecount -eq 0 ]]; then
        echo "* No mp3's found in $sourceDir"
        exit 1
    fi

    echo "* Screening directory for unformatted filenames"
    echo "****"
    unformatted="$(screen_directory_names "$sourceDir" | tail -n 1)"
    if [[ $unformatted -gt 0 ]]; then
        cat > /dev/tty << EOF

******** Warning: Couldn't parse the $unformatted filenames above ********

These files will not be included in packs until qPack renames them with a
minimum of year and bitstring. You can use qPackRename.sh as a standalone tool
or the r command from qPack to rename them. 

Audiobookshelf's default behavior is to watch the files and update its
database with any filename changes so that renamed files will not go missing.

EOF
        if [[ "$filecount" == "$unformatted" ]]; then # there aren't any formatted files to pack
            echo "******** You must allow qPack to rename files for it to pack them ********"
            echo
            #exit 1
        fi
        echo You may proceed if you want qPack to ignore the listed files.
        read -p "Would you like to continue? [Yn] : " yn
        if [[ $yn == "n" || $yn == "N" ]]; then
            exit 0
        fi
    fi

    echo "* Examining mp3 filenames for release years and bitrates sourced from mediainfo"
    year_filecount=()
    year_filesize=()
    bitrate_totals=()
    year_filesize=()
    year_bitrate_counts=()
    populate_year_arrays "$sourceDir"
}

########################### nextJob functions ###########################
#
#  This is the meat & potatoes of qPack.sh's implementation of qPack's
#   overall function library. The idea here is to be able to run w/o
#   arguments for newer users to have a fully interactive mode, then to
#   have the CLI invocation available for those who care to use the tools
#   without the TUI on the CLI or want to script functionality. The end
#   goal would be an argument that will allow the user to specify a file
#   with one set of CLI arguments per line and qPack.sh will iterative
#   through that batch using read_next_job for each set of arguments
#

########################### set_nextJob() ###########################
#
#  Populate the nextJob variable with the appropriate value given
#    arguments provided
#
set_nextJob() {
    local i1="$1" # Action
    local i2="$2" # Parameter / beginning year
    local i3="$3" # Possible end of range

    case $i1 in
        r )
            shift
            local renameParams="$*"
            scriptDir="$(resolve_init_script_path "$0")"
            local renameSh="${scriptDir}/qPackRename.sh"
            if [[ -f "$renameSh" ]]; then 
                $renameSh "$sourceDir" $renameParams
                # We want to update the arrays with the new filename metadata.
                # We don't want filename warnings on dry runs or samples.
                local refresh="1"
                for param in $refresh_params; do
                    if [[ "$param" == *"--show-samples"* || "$param" == *"--dry-run"* ]]; then
                        refresh="0"
                    fi
                done
                if [[ "$refresh" == "1" ]]; then
                    echo "* Updating sourceDir metadata"
                    initSourceDir # update arrays with filename metadata
                fi
            else
                echo "ERROR: qPackRename.sh not found at $renameSh" 1>&2
            fi
            nextJob=""
            ;;
        rh ) cat << EOF

Parameters for the r command:
    --dry-run               : Show new filenames with the options tested
                               without renaming them. ALWAYS TEST FIRST
    -t, --podcast-title     : Set the podcast title (default is <target
                               directory name>)
    -d, --date-name         : Template 0 with no season/episode lookups. Fast.
    -f #                    : Format according to template # from samples
    --show-samples          : Pick out random files and show sample output with
                               all templates defined in the script (hint, hint)

Safe usage examples:
r --show-samples
r -d --dry-run
r -f 2 --dry-run

EOF
        ;;
        "thumb" )
            nextJob="--thumb "$savePath" "$thumbPath""
            ;;
        p )
            "$scriptDir"/resources/printOptionReport.sh "$sourceDir"
            nextJob=""
            ;;
        pq )
            local qJob
            local qDir
            echo "Job queue:"
            for job in "${jobQueue[@]}"; do
                IFS='|' read -r qJob qDir <<< "$job"
                echo "'$qJob' in '$qDir'"
            done
            ;;
        run )
            nextJob="run"
            ;;
        o )
           packOption="$i2"
            if [[ ! -z "$packOption" ]]; then
                nextJob="-o $packOption"
            else
                echo "o option must be followed by option number"
                nextJob=""
            fi
            ;;
        t1 | ta )
            # We'll try to take year1 and year2 as arguments
            # It can be difficult not to enter these as a range with a -
            # the local variables and set_y1_y2 allow us to accept
            # either format: y1 y2 or y1-y2
            year1="$i2"
            year2="$i3"            
            local y1=""
            local y2=""
            set_y1_y2 "$year1"
            if [[ ! -z "$y2" ]]; then # the user entered a y1-y2 range instead of y1 y2, which are hopefully valid
                year1="$y1"
                year2="$y2"
            fi

            if [[ -z "$year1" ]]; then 
                nextJob="-${i1}" # the function library will do all of them
            else
                if [[ $year1 =~ ^[12][0-9]{3}$ ]]; then # it wasn't actually another year
                    if [[ -z "$year2" ]]; then
                        nextJob="-${i1} $year1"
                    else
                        if [[ $year2 =~ ^[12][0-9]{3}$ ]]; then # it wasn't actually another year
                            nextJob="-${i1} $year1 $year2"
                        else
                            echo "-${i1} year '$year2' invalid" > /dev/tty
                        fi
                    fi
                else
                    echo "-${i1} year '$year1' invalid" > /dev/tty
                    nextJob=""
                fi
            fi
            ;;
        cd )
            # Set the sourceDir to the remainder of arguments.
            # initSourceDir will prompt interactively if this is blank
            shift

            sourceDir="$*"
            if [[ ! -z  "$sourceDir" ]]; then
                if [[ -d "$sourceDir" ]]; then
                    sourceDir="$(cd "$sourceDir" && pwd)"
                elif [[ -d "$mediaPath" && -d "$(realpath "$mediaPath/$sourceDir")" ]]; then
                    sourceDir="$(realpath "$mediaPath/$sourceDir")"
                else
                    sourceDir=""
                fi
            fi
            initSourceDir
            nextJob=""
            ;;
        q | Q )
            nextJob=""
            qPackDone="1"
            ;;
        * )
            nextJob="unknown"
            ;;
    esac
}

########################### read_next_job() ###########################
#
#  Interactively read the next job to be executed

read_next_job() {
    echo "Source directory: $sourceDir"
    read -p "Choose menu option [?] : " input
    read -r i1 i2 i3 <<< "$input"
    i1=${i1:=""}
    i2=${i2:=""}
    i3=${i3:=""}

    set_nextJob "$i1" "$i2" "$i3"
}

# *****************************
# 1. Source in qPack functions
# 2. Populate variables from qPack configuration
# 3. Populate variables from the environment
# 4. Validate required information is populated
init_config() {
    scriptDir="$(resolve_init_script_path "$0")"
    source "${scriptDir}/resources/qWrapper.sh"

    declare -g savePath=$(get_config_value "Local" "savePath")
    declare -g mediaPath=$(get_config_value "Local" "mediaPath")
    declare -g thumbPath=$(get_config_value "Local" "thumbPath")
    declare -g torrentDataPath=$(get_config_value "Local" "torrentDataPath")
    declare -g errorLogPath=$(get_config_value "Local" "errorLogPath")
    declare -g local_watchPath=$(get_config_value "Local" "watchPath")
    declare -g lnOrCp=$(get_config_value "Local" "lnOrCp")
    declare -g announceUrl=$(get_config_value "Tracker" "announceUrl")
    declare -g seedUser=$(get_config_value "Seedbox" "seedUser")
    declare -g seedPath=$(get_config_value "Seedbox" "seedPath")
    declare -g seedServer=$(get_config_value "Seedbox" "seedServer")
    declare -g seed_watchPath=$(get_config_value "Seedbox" "watchPath")
}


# Command line arguments when qPack.sh is invoked
process_args() {
    sourceDir=""
    podcastName=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n | --podcast-name)
                shift
                podcastName=$(get_ntfs_safe "$1") # this will overwrite the title assumed by the target if that was found first
                ;;
            -h | -\? | --help)
                show_help
                exit 0
                ;;
            *)
                #$(realpath "${target_dir}/${selected_relative}")
                if [[ -d "$mediaPath" ]]; then
                    mediaPath=${mediaPath%/}
                fi
                if [[ -z  "$sourceDir" ]]; then # we haven't already set a sourceDir
                    if [[ -d "$1" ]]; then
                        sourceDir="$(cd "$1" && pwd)"
                    elif [[ -d "$mediaPath" && -d "$(realpath "$mediaPath/$1")" ]]; then
                        sourceDir="$(realpath "$mediaPath/$1")"
                    else
                        echo "Not a known option or source directory: " "$1"
                        echo "${0##*/} -h for usage"
                        exit 1
                    fi
                else # we already have a directory set....?
                    echo "Unknown option" "$1"
                fi
                ;;
        esac
        shift
    done
}

echo "***********************"
echo "* qPack Initializing..."
init_config
process_args "$@"
echo \* Args processed
initSourceDir

echo "* Done."
echo

declare -g qPackDone=0
while [[ $qPackDone == 0 ]]; do
    echo "scriptDir $scriptDir" > /dev/tty
    read_next_job > /dev/tty
    if [[ ! -z "$nextJob" ]]; then
        if [[ "$nextJob" == "unknown" ]]; then
            show_menu > /dev/tty
        elif [[ "$nextJob" == "run" ]]; then
            # Execute all queued jobs
            for job in "${jobQueue[@]}"; do
                # Extract sourceDir and job string
                IFS='|' read -r sourceDir jobString <<< "$job"
                execute_job "$sourceDir" "$jobString"
            done

            # Clear the queue
            jobQueue=()
        else
            # Queue the job
            echo "Queue addition: '$nextJob' in '$sourceDir'"
            jobQueue+=("$sourceDir|$nextJob")
        #else
        #    execute_job "$sourceDir" "$nextJob"
        fi
        nextJob=""
    fi
done

echo 
echo Thank you for using qPack.
echo