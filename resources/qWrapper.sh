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
        echo "No config file found at $CONFIG_FILE. Please run qPackConfig." 1>&2
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
        echo "qWrapper: Log name not set." 1>&2
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
    local announceUrl
    # Falling back to config instead of requiring the announce makes it 
    # friendlier for standalone usage if a user sources qWrapper.sh for 
    # use on the CLI
    if [[ -n "$3" ]]; then
        announceUrl="$3"
    else
        announceUrl=$(get_config_value "Tracker" "announceUrl")
    fi
    local outputFile
    local outputTitle
    # Optionally set a custom torrent title
    if [[ ! -z "$2" ]]; then
        outputTitle="$2"
        titleOption="-n $outputTitle"
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
    mktorrent -a "$announceUrl" -p -s "Unwalled" $titleOption -o "$outputFile" "$target" > /dev/null
    
    if [[ $? -eq 0 ]]; then
        echo $outputFile
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