#!/bin/bash

SECONDS=0
set -e

# Function to display help message
show_help() {
    cat << EOF
qTorSync - part of the qPack toolset

Standalone tool to create a .torrent file, save it, and optionally:
* Save another copy to a watch folder
* rsync the data to a remote host
* rsync the .torrent to a watch directory on the remote host

Usage: ${0##*/} [OPTIONS] <local_target> [remote_dir]

<local_target> is the path to the local file or directory target. 
[remote_dir] is an optional path to the remote directory. Begin with /
             (defaults to the seedbox directory set in qPackConfig)

Options:
    -n <name>               : Specify torrent name (defaults to target basename)
    -h, --help              : Show this help message
EOF
}

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
init_config() {
    scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"/resources
    source "${scriptDir}/qWrapper.sh"

    savePath=$(get_config_value "Local" "savePath")
    torrentDataPath=$(get_config_value "Local" "torrentDataPath")
    errorLogPath=$(get_config_value "Local" "errorLogPath")
    local_watchPath=$(get_config_value "Local" "watchPath")
    announceUrl=$(get_config_value "Tracker" "announceUrl")
    seedUser=$(get_config_value "Seedbox" "seedUser")
    seedPath=$(get_config_value "Seedbox" "seedPath")
    seedServer=$(get_config_value "Seedbox" "seedServer")
    seed_watchPath=$(get_config_value "Seedbox" "watchPath")

    # List to hold any missing config tag names
    missingTags=()

    # Confirm that required config values are populated
    [ -z "$savePath" ] && missingTags+=("savePath")
    [ -z "$announceUrl" ] && missingTags+=("announceUrl")

    # Check if there are missing tags
    if [ ${#missingTags[@]} -ne 0 ]; then
        echo "The following tags need to be populated: ${missingTags[*]}"
        echo "Please run qPackConfig."
        exit 1
    fi
}

process_args() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    target=""
    podcastName=""
    torrentName=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n)
                torrentName="$2"
                shift
                ;;
            -h | -\? | --help)
                show_help
                exit 0
                ;;
            *)
                # The non-option is the target (or remote directory)
                if [[ -z  "$target" ]]; then # we haven't already set a mediaDir
                    if [[ -d "$1" ]]; then
                        target="$1"
                        target="${target%/}" # Ensure we don't have a trailing slash
                    elif [[ -f "$1" ]]; then
                        target="$1"
                    elif [[ -z "$torrentDataPath" ]]; then
                        if [[ -d "$torrentDataPath/$1" ]]; then
                            target="$torrentDataPath/$1"
                            target="${target%/}" # Ensure no trailing slash
                        elif [[ -f "$torrentDataPath/$1" ]]; then
                            target="$torrentDataPath/$1"
                        fi
                    else
                        echo "ERROR: Unknown option \'$1\' is also not a directory to target"
                        show_help
                        exit 1
                    fi
                    if [[ -d "$target" ]]; then
                        logName=$(basename "$target")
                    else
                        logName=$(basename "$(dirname "$(realpath "$target")")")
                    fi
                else # we already have a directory set....?
                    if [[ -z "$seedPath" ]]; then
                        echo Overridding $seedpath with $1
                    fi
                    seedPath="$1"                        
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
echo 
if [[ -z $target ]]; then
    echo "ERROR: No target specified"
    show_help
    exit 1
fi
if [[ ! -n $errorLog ]]; then
    init_error_log "$logName"
    echo \* Setting errorLog
    errorLog="$(echo $errorLog | tail -n 1)"
fi
if [[ -z $errorLog ]]; then
    echo "Error initializing error log for $podcastName."
    exit 1
fi
echo "* Done."
echo
file=$(create_torrent "$target" "$torrentName")
file=$(echo $file | tail -n 1)
# Check if the function succeeded and use the result
if [[ $? -eq 0 ]]; then
    echo "Saved torrent $file"
    if [[ $local_watchPath != "" ]]; then # save another copy to the local watch path
        cp "$file" "$local_watchPath"
        echo "Saved torrent to $local_watchPath"
    fi
else
    echo "Error creating torrent." >&2
fi
if [[ $seedUser != ""  ]]; then # sync the torrent data to the user's seedbox
    echo "*******************************"
    echo "Sending torrent data to seedbox"
    sync_to "$target"
    echo "*******************************"
    if [[ $seed_watchPath != "" ]]; then # sync the .torrent file to the user's seedbox's client's watch directory
        echo "Sending torrent file to seedbox"
        sync_to "$file" "1"
        echo "*******************************"
    fi
fi
echo
echo Complete
echo
time_report $SECONDS
exit 0