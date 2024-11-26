#!/bin/bash

SECONDS=0
set -e

# Default values or functions to fetch them
declare -A templateVars=(
    ["yyyymmdd"]="get_releaseSortDate"
    ["Snn"]="get_Snn"
    ["Enn"]="get_Enn"
    ["Ennn"]="get_Ennn"
    ["podcastName"]="get_podcastName"
    ["episodeTitle"]="get_episodeTitle"
    ["YEAR"]="get_year"
    ["bitString"]="get_bitString"
)

declare -A templateFmts=(
    ["d"]="{podcastName} - {yyyymmdd} - {episodeTitle} [{YEAR}/MP3-{bitString}].mp3"
    ["d_e"]="{podcastName} - {yyyymmdd} - {Ennn}-{episodeTitle} [{YEAR}/MP3-{bitString}].mp3"
    ["d_ssee"]="{podcastName} - {yyyymmdd} - S{Snn}E{Enn}-{episodeTitle} [{YEAR}/MP3-{bitString}].mp3"
    ["ssee"]="{podcastName} - S{Snn}E{Enn} - {episodeTitle} [{YEAR}/MP3-{bitString}].mp3"
    ["sseee"]="{podcastName} - S{Snn}E{Ennn} - {episodeTitle} [{YEAR}/MP3-{bitString}].mp3"
)

# Indexed array of keys from templateFmts for numerical indexing
#              0    1      2       3       4
templateKeys=("d" "d_e" "d_ssee" "ssee" "sseee")

# ****************************************************************************
# init_config() imports library functions and populates variables that qPack
#   uses as environment variables within. Each script serves as the primary
#   subshell for its qPack tool into which the wrapper needs to be imported.
# This allows qPack tools to have different implementations to suit different
#   use cases
# ****************************************************************************
# 1. Source in qPack functions
# 2. Populate variables from qPack configuration
# 3. Populate variables from the environment
# 4. Validate required information is populated
init_config() {
    scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"/resources
    source "${scriptDir}/qWrapper.sh"

    replacementChar=$(get_config_value "Local" "replacementChar")
    seriesTag=$(get_config_value "Tags" "seriesTag")
    episodeTag=$(get_config_value "Tags" "episodeTag")
    dateTag=$(get_config_value "Tags" "dateTag")

    # Grab the media path, if available, to allow for directory-only invokation
    mediaPath=$(get_config_value "Local" "mediaPath")

    # List to hold any missing config tag names
    missingTags=()

    # Confirm that required config values are populated
    [ -z "$replacementChar" ] && missingTags+=("replacementChar")
    [ -z "$seriesTag" ] && missingTags+=("seriesTag")
    [ -z "$episodeTag" ] && missingTags+=("episodeTag")
    [ -z "$dateTag" ] && missingTags+=("dateTag")

    # Check if there are missing tags
    if [ ${#missingTags[@]} -ne 0 ]; then
        echo "The following tags need to be populated: ${missingTags[*]}"
        echo "Please run qPackConfig."
        exit 1
    fi
}

# Function to display help message
show_help() {
    cat << EOF
qPackRename - part of the qPack toolset

Renames files named {title}.mp3 into specified format template. 
Looks up metadata using mediainfo with tags specified in qPackConfig.sh
Run with --show-samples for options (maximize terminal first).
Progress to -f # --dry-run to see full preview of new filenames.

Usage: ${0##*/} [OPTIONS] <target directory of podcast mp3 files>
Options:
    --dry-run               : Show what new filenames would be with the options
                               used without renaming them. ALWAYS TEST FIRST
    -t, --podcast-title     : Set the podcast title (default is <target
                               directory name>)
    -d, --date-name         : Template 1 with no season/episode lookups. Fast.
    -f #                    : Format according to template # from samples
    --show-samples          : Pick out random files and show sample output with
                               all templates defined in the script (hint, hint)

    -h, --help              : Show this help message
EOF
}

process_args() {
    dry="0"
    fmt="0"
    # Process command-line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run | --dry-run-only)
                dry="1"
                ;;
            -t | --podcast-title)
                shift
                podcastName=$(get_ntfs_safe "$1") # this will overwrite the title assumed by the target if that was found first
                ;;
            -d | --date-name)
                fmt="d"
                ;;
            -f)
                shift
                fmt="${templateKeys[$1]}"
                if [[ -z "$fmt" ]]; then
                    echo "Not a recognized format option \"$1\""
                    sample="1"
                fi
                ;;
            --show-samples)
                sample="1"
                ;;
            -h | -\? | --help)
                show_help
                exit 0
                ;;
            *)
                # The non-option is the target
                if [[ -z  "$mediaDir" ]]; then # we haven't already set a mediaDir
                    if [[ -d "$1" ]]; then
                        mediaDir="$(cd "$1" && pwd)"
                    elif [[ -d "$mediaPath/$1" ]]; then
                        mediaDir="$mediaPath/$1"
                    else
                        echo "ERROR: Unknown option \'$1\' is also not a directory to target"
                        show_help
                        exit 1
                    fi
                    if [ -z "$podcastName" ]; then # then it wasn't explicitly set by argument
                        podcastName=$(get_ntfs_safe "$(basename "$mediaDir")")
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

if [[ ! -n $errorLog ]]; then
    echo \* Setting errorLog
    init_error_log "$podcastName"
    errorLog="$(echo $errorLog | tail -n 1)"
fi
if [[ -z $errorLog ]]; then
    echo "Error initializing error log for $podcastName."
    exit 1
fi
echo "* Done."
echo

if [[ "$sample" == "1" ]]; then
    show_samples "$mediaDir" "$podcastName"
else
    rename_dir "$mediaDir" "$podcastName" "$dry" "$fmt"
fi

time_report $SECONDS
exit 0