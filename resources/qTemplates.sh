#!/bin/bash

## This is the library that qPack uses to process templates
# 

# Function definitions for dynamic value lookup. One is needed for each dynamic variable. 
# $file must be poopulated and other referenced variables must be set in the environment.
# 
get_releaseSortDate() { # {yyyy.mm.dd} - The release date in yyyy.mm.dd format
    date -d "$(mediainfo "$file" | grep "$dateTag" | cut -c 44-59)" +%F | sed 's/-/./g'
}

get_Snn() { # The season numbers in 2 digits, e.g. 02
    printf "%02d" "$(mediainfo "$file" | grep "$seriesTag" | cut -c 44-99 | xargs | sed 's/^0*//')"
}

get_Enn() { # The episode numbers in 2 digits, e.g. 01
    printf "%02d" "$(mediainfo "$file" | grep "$episodeTag" | cut -c 44-99 | xargs | sed 's/^0*//')"
} 

get_Ennn() { # The episode numbers in 3 digits, e.g. 001
    printf "%03d" "$(mediainfo "$file" | grep "$episodeTag" | cut -c 44-99 | xargs | sed 's/^0*//')"
} 

get_podcastName() {
    # This extraction method avoids the bug in many cut version for international characters
    name="$(mediainfo "$file" | grep "Album  " | awk '{print substr($0, 44)}' | sed 's/(subscriber edition)//' | sed 's/^[ \t]*//;s/[ \t]*$//')"
    echo "$name" | xargs -0
}

get_episodeTitle() {
    echo ${file%.*}
}

get_year() {
    date -d "$(mediainfo "$file" | grep "$dateTag" | cut -c 44-59)" +%Y
}

get_bitString() {
    mediainfo "$file" | grep 'Bit\ rate\ \  ' | cut -c 44-99 | xargs | sed 's/\//p/' | sed 's/\.0//'
}

#
# Sets $newFile to format specified
#
# Usage: format_filename <dir> <file> <template> <podcastName> [bitString] [year] [month] [day]
#
# Description:
#   Formats an NTFS-legal filename using a user-provided template allowing the following substitutions:
#     {yyyy.mm.dd} - The release date in yyyy.mm.dd format
#     {Snn}  - The season numbers in 2 digits, e.g. 02
#     {Enn}  - The episode number (always 2-digit, e.g. 02)
#     {Ennn} - The episode number (always 3-digit, e.g. 002)
#     {podcastName} - The podcast name
#     {episodeTitle} - The episode title
#     {year} - the release year in yyyy
#
#   qPack will retrieve all metadata not specified in the parameters

format_filename() { 
    local dir="$1"
    local file="$2"
    local templateBlank="$3"
    local podcastName="$4"
    local bitString="$5"
    local year="$6"

    if [[ -z $dir || -z $file || -z $templateBlank ]]; then
        echo "ERROR: format_filename() requires 3 parameters" >&2
        if [[ ! -n $errorLog ]]; then
            touch $errorLog
            echo "ERROR: format_filename() requires 3 parameters" >> $errorLog
            exit 1
        fi
    fi

    local result="$templateBlank"

    for key in "${!templateVars[@]}"; do
        value="$(${templateVars[$key]})"
        result="${result//\{$key\}/$value}"
        case $value in
            "podcastName" )
                if [[ -z "$podcastName" ]]; then
                    result="${result//\{$key\}/$podcastName}"
                else
                    result="${result//\{$key\}/$podcastName}"
                fi
                ;;
            *) 
                result="${result//\{$key\}/$value}"
                ;;
        esac
    done

    # Overrides
    if [[ -z $podcastName ]]; then
        result="${result//\{podcastName\}/$podcastName}"
    fi
    if [[ -z $bitString  ]]; then
        result="${result//\{bitString\}/$bitString}"
    fi
    if [[ -z $YEAR ]]; then
        result="${result//\{YEAR\}/$YEAR}"
    fi

    #newFile=$result
    newFile=$(get_ntfs_safe "$result")
}

# Usage rename_dir <mediaDir> <podcastName> <dry> <templateString>
rename_dir() {
    local mediaDir="$1"
    local podcastName="$2"
    local dry="$3"
    local templateString="$4"

    case $templateString in # These are the keys and corresponding strings defined (hint, hint)
        "d" )
            templateString="{podcastName} - {yyyymmdd} - {episodeTitle} [{YEAR}/MP3-{bitString}].mp3"
            ;;
        "d_e" )
            templateString="{podcastName} - {yyyymmdd} - {Ennn}-{episodeTitle} [{YEAR}/MP3-{bitString}].mp3"
            ;;
        "d_s" )
            templateString="{podcastName} - {yyyymmdd} - S{Snn}-{episodeTitle} [{YEAR}/MP3-{bitString}].mp3"
            ;;
        "d_ssee" )
            templateString="{podcastName} - {yyyymmdd} - S{Snn}E{Enn}-{episodeTitle} [{YEAR}/MP3-{bitString}].mp3"
            ;;
        "ssee" )
            templateString="{podcastName} - S{Snn}E{Enn} - {episodeTitle} [{YEAR}/MP3-{bitString}].mp3"
            ;;
        "sseee" )
            templateString="{podcastName} - S{Snn}E{Ennn} - {episodeTitle}  [{YEAR}/MP3-{bitString}].mp3"
            ;;
        * )
            echo "**********"
            echo "ERROR: Invalid template string"
            echo "**********"
            echo qPack can rename according to a number of pre-defined templates.
            echo Specify from one of the following options:
            show_samples "$mediaDir" "$podcastName"
            exit 1
            ;;
    esac 

    # Initialize summary variables
    renameCount=0
    skipCount=0
    errorCount=0

    if [[ $dry == "1" ]]; then
        echo "Performing dry run for "$podcastName". Only proposed changes will be shown."
    else
        echo Renaming files for podcast "$podcastName"
    fi
    echo Entering $mediaDir
    cd "$mediaDir"

    for file in *.mp3; do
        # Check if already renamed
        if [[ $file =~ ^${podcastName}.*\[.*\].mp3$ ]]; then
            skipCount=$((skipCount + 1))
            continue
        fi

        bitString=$(mediainfo "$file" | grep 'Bit\ rate\ \  ' | cut -c 44-99 | xargs | sed 's/\//p/')
        year=$(date -d "$(mediainfo "$file" | grep 'releasedate' | cut -c 44-59)" +%Y)

        # If we don't see these then something is wrong
        if [[ -z $bitString || -z $year ]]; then
            echo "$file: bitrate or year missing"
            echo $file
            pwd
            exit 1
            echo "$file: bitrate or year missing" >> $errorLog
            errorCount=$((errorCount + 1))
            continue
        else
            # Rename the file, including the info we've already checked, and
            #   increment the counter if successful
            
            # Loop through each placeholder in the template and populate the variables for this file
            for key in "${!templateVars[@]}"; do
                if [[ $templateString == *"{$key}"* ]]; then
                    if [[ $(declare -F "${templateVars[$key]}") ]]; then
                        declare "$key"="$(${templateVars[$key]})"
                    else
                        declare "$key"="${templateVars[$key]}"
                    fi
                fi
            done

            newFile=""
            format_filename "$mediaDir" "$file" "$templateString" "$podcastName" "$bitString" "$year"
            if [[ "$newFile" != "" ]]; then
                if  [[ "$dry" == "1" ]]; then
                    echo "$newFile" && renameCount=$((renameCount + 1))
                else
                    mv "$file" "$newFile" && renameCount=$((renameCount + 1))
                fi
            fi
        fi
    done
    if [[ $dry == "1" ]]; then
        echo "Proposed $renameCount filenames"
    else
        echo "Renamed $renameCount files"
    fi
    echo "Skipped $skipCount files"


    echo "Logged $errorCount errors"
    if [[ $errorCount > 0 ]]; then echo "Errors logged to $errorLog"; fi
}

# Usage: show_samples [mediaDir]
#
# Shows samples of all defined format templates (hint, hint) in [mediaDir]
show_samples() {
    mediaDir="$1"
    if [[ -z "$mediaDir" || ! -d "$mediaDir" ]]; then
        echo "ERROR: No valid directory provided: $mediaDir"
        exit 1
    elif [[ ! -z "$mediaDir" ]]; then
        echo Entering $mediaDir
        cd "$mediaDir"
    fi
    
    echo "Picking a few random files for samples..."
    mapfile -t mp3_files < <(ls *.mp3 | shuf -n 3)
    for file in "${mp3_files[@]}"; do
        echo "Sample output for file \"$file\" by template format # for -f # option:"
        for i in "${!templateKeys[@]}"; do
            templateKey="${templateKeys[$i]}"
            sample_templateString=${templateFmts[$templateKey]}
            format_filename "$mediaDir" "$file" "$sample_templateString"
            echo "$i-> $newFile"
        done
        echo
    done
}
