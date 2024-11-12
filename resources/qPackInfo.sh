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
            if [["$errorLog"!= ""]]; then
                echo "Warning: Can't parse filename: $filename" >> "$errorLog"
            fi
        fi
    done < <(find "$mediaDir" -type f -name '*.mp3' -print0)
}

# Populate bitString and bitPercentage with the average bitrateString 
# and the percent of files w for the years provided as a list of arguments
# Usage: populate_bitString <year> [year2] [year3] [...]
function populate_bitString() {
    for year in "$@"; do
        total_files_all=0
        total_size_all=0
        max_count=0
        common_bitrate=""
        for key in "${!year_bitrate_counts[@]}"; do
            IFS='|' read -r key_year bitrate <<< "$key"
            if [ "$key_year" == "$year" ]; then
                count=${year_bitrate_counts["$key"]}
                bitrate_totals[$bitrate]+=$((bitrate_totals[$bitrate]+=$count))
                if [ "$count" -gt "$max_count" ]; then
                    max_count=$count
                    common_bitrate="$bitrate"
                fi
            fi
        done

        # Calculate the percentage of files with the most common bitrate string
        bitPercentage=$(awk "BEGIN { if ($total_files > 0) printf \"%.2f\", ($max_count/$total_files)*100; else print \"0.00\" }")
    done
    
}

# Screen a directory, ensuring that mp3's have the year and bitrate
#
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
