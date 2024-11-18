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

# Function to display help message
show_help() {
    cat << EOF

Usage: ${0##*/} [OPTIONS] [source directory]

Options:
    -n                 : Specify the podcast name (defaults to directory name)
    -h, --help         : Show this help message
EOF
}

show_menu() {
    cat << EOF

Select an option:
thumb           : Save a thumbnail for the working directory
p               : Print a torrent options report for "o <#>"
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
q               : Quit
?               : Print this menu
EOF
}

########################### read_next_job() ###########################
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
read_next_job() {
    read -p "Choose menu option [?] : " input
    read -r i1 i2 i3 <<< "$input"
    i1=${i1:=""}
    i2=${i2:=""}
    i3=${i3:=""}

    case $i1 in
        "thumb" )
            nextJob="--thumb "$savePath" "$thumbPath""
            ;;
        p )
            local resourceDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"/resources
            "$resourceDir"/printOptionReport.sh "$sourceDir"
            nextJob=""
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
        q | Q )
            nextJob=""
            qPackDone="1"
            ;;
        * )
            show_menu > /dev/tty
            ;;
    esac

    #echo $nextJob
}

# *****************************
# 1. Source in qPack functions
# 2. Populate variables from qPack configuration
# 3. Populate variables from the environment
# 4. Validate required information is populated
init_config() {
    scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"/resources
    source "${scriptDir}/qWrapper.sh"

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

# Begin interactive mode as needed
if [[ -z "$sourceDir" ]]; then # we must get it populated interactively
    sourceDir="$(read_relative_path "Data source directory" "$torrentDataPath" "1" | tail -n 1)"
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
unformatted="$(screen_directory_names "$sourceDir" | tail -n 1)"
if [[ $unformatted -gt 0 ]]; then
    cat > /dev/tty << EOF

******** Warning: Couldn't parse the $unformatted filenames above ********

These files must have qPack-friendly names for qPack tools.
qPackRename.sh is designed to give {title}.mp3 files useful names.

EOF
    if [[ "$filecount" == "$unformatted" ]]; then # there aren't any formatted files to pack
        echo "******** Renaming can still only done with qPackRename.sh ********"
        echo "******** Run qPack.sh on the same directory once complete ********"
        echo
        exit 1
    fi
    echo You may proceed if you want qPack to ignore the listed files.
    read -p "Would you like to continue? [Yn] : " yn
    if [[ $yn == "n" || $yn == "N" ]]; then
        exit 0
    fi
fi

echo "* Examining mp3 filenames for release years and bitrates sourced from mediainfo"
populate_year_arrays "$sourceDir"

echo "* Done."
echo

declare -g qPackDone=0
while [[ $qPackDone == 0 ]]; do
    read_next_job > /dev/tty
    if [[ ! -z "$nextJob" ]]; then
        execute_job "$sourceDir" "$nextJob"
        nextJob=""
    fi
done

echo 
echo Thank you for using qPack.
echo