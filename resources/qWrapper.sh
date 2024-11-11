#!/bin/bash

CONFIG_FILE="$HOME/.qPack_config"
scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${scriptDir}/qDev.sh"
source "${scriptDir}/qTemplates.sh"

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
        echo "No config file found at $CONFIG_FILE. Please run qPackConfig." >&2
        exit 1
    fi
}

# Function to get the error log path
# Usage
init_error_log() {
    local podcast_title="$1"
    local yn
    errorLogPath=$(get_config_value "Local" "errorLogPath")
    if [[ -z "$errorLogPath" ]]; then
        echo "Error log path not set. Please run qPackConfig."
        exit 1
    fi
    errorLogPath="${errorLogPath%/}"
    if [[ ! -d "${errorLogPath}" ]]; then
        echo "Creating error log directory: ${errorLogPath}"
        echo "(debug, shouldn't have to make it)"
        exit 1
        #mkdir -p "${errorLogPath}"
        # echo "Would you like to make it?"
        # read -p "y/n" yn
        # if [[ $yn == [Yy] ]]; then
        #     mkdir -p "${errorLogPath}"
        # fi
    fi
    #if [[ -n "$podcastName" || -z "$podcastName" ]]; then
    if [[ -z "$podcastName" ]]; then
        echo "Podcast title not set."
        exit 1
    else
        errorLog="${errorLogPath}/error-${podcastName}.log"
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
