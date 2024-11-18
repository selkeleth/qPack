#!/bin/bash

# This library needs declare -A year_filecount, year_filesize, year_bitrate_counts, bitrate_totals arrays in the calling environment
# $year_filecount is an array of the number of files in each year
# $year_filesize is an array of the size of each file in each year
# $year_bitrate_counts is an array of the number of bitrate counts in each year
# $bitrate_totals is an array of the total number of bitrate counts in a requested span of years
#
# Use the following function to populate these arrays once declared
# Usage: populate_year_arrays <directory>
#        <directory> selects location to analyze by filename
function populate_year_arrays() {
    mediaDir="$1"
    current_year=$(date +%Y)
    noparse=0

    while IFS= read -r -d '' file; do
        filename="$(basename "$file")"

        # Extract the year and bitrateString from the filename
        if [[ "$filename" =~ \[([0-9]{4})_MP3-([^\]]+)\] ]]; then
            year="${BASH_REMATCH[1]}"
            bitrateString="${BASH_REMATCH[2]}"
            year_filecount[$year]=$((year_filecount[$year]+1))
            filesize=$(stat -c%s "$file")
            year_filesize[$year]=$((year_filesize[$year]+$filesize))

            # Increase the count for the bitrate string for the year
            bitrate_key="${year}|${bitrateString}"
            year_bitrate_counts[$bitrate_key]=$((year_bitrate_counts[$bitrate_key]+1))
        else
            echo "Warning: Can't parse filename: $filename" >&2
            noparse=$((noparse + 1))            
            # if [[ ! -z "$errorLog" ]]; then
            #     if [[ ! -f "$errorLog" ]]; then
            #         touch "$errorLog"
            #     fi
            #     echo "Warning: Can't parse filename: $filename" >> "$errorLog"
            # fi
        fi
    done < <(find "$mediaDir" -type f -name '*.mp3' -print0)
    #echo $noparse
}

# Populate bitString and bitPercentage with the average bitrateString 
# and the percent of files w for the years provided as a list of arguments
# Usage: populate_bitString <directory> <year> [year2] [year3] [...]
function populate_bitString() {
    local dir="$1"
    shift
    local yearlist
    if [[ -z "$@" ]]; then # do all the years
        yearList="${!year_filecount[@]}"
    else
        yearList="$@"
    fi
    local -A bitrate_count
    local total_files=0
    for year in $yearList; do
        # We don't have a matrix of bitrateStrings by year to analyze
        # It's cheaper to make them on the fly for spans requested
        for file in "${dir}"/*.mp3; do
            # Extract year and bitrate using regex
            if [[ $file =~ \[(20[0-9]{2})_MP3-([^\]]+)\] ]]; then
                file_year="${BASH_REMATCH[1]}"
                bitrate="${BASH_REMATCH[2]}"
                bitrate="${bitrate/%.0 kbps/ kbps}"
                # Check if extracted year is in the provided years list
                if [[ " ${yearList[@]} " =~ " $file_year " ]]; then
                    bitrate_count[$bitrate]=$((bitrate_count[$bitrate] + 1))
                    total_files=$((total_files + 1))                    
                fi
            fi
        done
    done

    # Find the most common bitrate
    bitString=""
    local max_count=0
    local bitrateCheck
    for bitrateCheck in "${!bitrate_count[@]}"; do
        if (( ${bitrate_count["$bitrateCheck"]} > max_count )); then
            max_count=${bitrate_count["$bitrateCheck"]}
            bitString="$bitrateCheck"
        fi
    done

    # Calculate the percentage
    if (( total_files > 0 )); then
        percentage=$(awk -v max_count="$max_count" -v total_files="$total_files" 'BEGIN { printf "%.0f", (max_count/total_files)*100 }')
    else
        percentage="0"
    fi
}

# Screen a directory, ensuring that mp3's have the year and bitrate
#
# "Returns" the number of files that qPack would skip
function screen_directory_names() {
    mediaDir="$1"
    skipCount=0

    while IFS= read -r -d '' file; do
        filename="$(basename "$file")"

        # Make sure the filenames matches for a year and a spot for a bitrateString
        if [[ ! "$filename" =~ \[([0-9]{4})_MP3-([^\]]+)\] ]]; then
            echo "Warning: Not expected format"
            echo $filename > /dev/tty
            skipCount=$((skipCount + 1))
        fi
    done < <(find "$mediaDir" -type f -name '*.mp3' -print0)

    echo $skipCount
}
