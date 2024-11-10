#!/bin/bash

# Check if the media directory is provided
if [ -z "$1" ]; then
    echo "Usage: $0 /path/to/mediaDir"
    exit 1
fi

mediaDir="$1"
current_year=$(date +%Y)

declare -A year_filecount
declare -A year_filesize
declare -A year_bitrate_counts

# Ensure numfmt is available for human-readable sizes
command -v numfmt >/dev/null 2>&1 || { echo "numfmt is required but it's not installed. Aborting." >&2; exit 1; }

# Find all MP3 files and process them
while IFS= read -r -d '' file; do
    filename="$(basename "$file")"

    # Extract the year and bitrateString from the filename
    if [[ "$filename" =~ \[([0-9]{4})_MP3-([^\]]+)\] ]]; then
        year="${BASH_REMATCH[1]}"
        bitrateString="${BASH_REMATCH[2]}"

        # Increase the file count for the year
        ((year_filecount["$year"]++))

        # Add the file size to the total size for the year
        filesize=$(stat -c%s "$file")
        ((year_filesize["$year"]+=filesize))

        # Increase the count for the bitrate string for the year
        bitrate_key="${year}|${bitrateString}"
        ((year_bitrate_counts["$bitrate_key"]++))
    else
        echo "Filename does not match pattern: $filename" >&2
    fi
done < <(find "$mediaDir" -type f -name '*.mp3' -print0)

echo "=== Annual Archive ==="
printf "%-10s %-10s %-15s %-25s %-10s\n" "Year" "Files" "Total Size" "Most Common Bitrate" "Percentage"

total_files_all=0
total_size_all=0
declare -A bitrate_totals
annual_data=()

for year in "${!year_filecount[@]}"; do
    total_files=${year_filecount["$year"]}
    total_size=${year_filesize["$year"]}
    ((total_files_all+=total_files))
    ((total_size_all+=total_size))

    # Find the most common bitrate string for the year
    max_count=0
    common_bitrate=""
    for key in "${!year_bitrate_counts[@]}"; do
        IFS='|' read -r key_year bitrate <<< "$key"
        if [ "$key_year" == "$year" ]; then
            count=${year_bitrate_counts["$key"]}
            ((bitrate_totals["$bitrate"]+=count))
            if [ "$count" -gt "$max_count" ]; then
                max_count=$count
                common_bitrate=$bitrate
            fi
        fi
    done

    # Calculate the percentage of files with the most common bitrate string
    percentage=$(awk "BEGIN { if ($total_files > 0) printf \"%.2f\", ($max_count/$total_files)*100; else print \"0.00\" }")

    # Format the total size to be human-readable
    readable_size=$(numfmt --to=iec --suffix=B --format="%.2f" "$total_size")
    
    # Accumulate data for sorting later
    annual_data+=( "$(printf "%s %s %s %s %s" "$year" "$total_files" "$readable_size" "$common_bitrate" "${percentage}%")" )
done

# Sort and print annual data
IFS=$'\n' sorted_annual_data=($(sort <<<"${annual_data[*]}"))
printf "%s\n" "${sorted_annual_data[@]}"

echo "=== Single Archive ==="
if [ "$total_files_all" -gt 0 ]; then
    common_total_bitrate=""
    common_total_count=0
    for bitrate in "${!bitrate_totals[@]}"; do
        if [ "${bitrate_totals["$bitrate"]}" -gt "$common_total_count" ]; then
            common_total_count=${bitrate_totals["$bitrate"]}
            common_total_bitrate=$bitrate
        fi
    done
    percentage_total=$(awk "BEGIN { printf \"%.2f\", ($common_total_count/$total_files_all)*100 }")
    readable_total_size=$(numfmt --to=iec --suffix=B --format="%.2f" "$total_size_all")
    printf "%-10s %-10s %-15s %-25s %-10s\n" "All" "$total_files_all" "$readable_total_size" "$common_total_bitrate" "${percentage_total}%"
else
    printf "%-10s %-10s %-15s %-25s %-10s\n" "All" "0" "0.00B" "" "0.00%"
fi

if [[ "${year_filecount["$current_year"]}" ]]; then
    echo "=== YTD + Archive ==="
    
    # YTD Section
    ytd_files=${year_filecount["$current_year"]}
    ytd_size=${year_filesize["$current_year"]}
    ytd_common_bitrate=""
    ytd_max_count=0
    for key in "${!year_bitrate_counts[@]}"; do
        IFS='|' read -r key_year bitrate <<< "$key"
        if [ "$key_year" == "$current_year" ]; then
            count=${year_bitrate_counts["$key"]}
            if [ "$count" -gt "$ytd_max_count" ]; then
                ytd_max_count=$count
                ytd_common_bitrate=$bitrate
            fi
        fi
    done
    ytd_percentage=$(awk "BEGIN { printf \"%.2f\", ($ytd_max_count/$ytd_files)*100 }")
    readable_ytd_size=$(numfmt --to=iec --suffix=B --format="%.2f" "$ytd_size")
    printf "%-10s %-10s %-15s %-25s %-10s\n" "YTD" "$ytd_files" "$readable_ytd_size" "$ytd_common_bitrate" "${ytd_percentage}%"
    
    # Archive Section
    archive_files=0
    archive_size=0
    declare -A archive_bitrate_counts
    for key in "${!year_bitrate_counts[@]}"; do
        IFS='|' read -r key_year bitrate <<< "$key"
        if [ "$key_year" != "$current_year" ]; then
            count=${year_bitrate_counts["$key"]}
            ((archive_bitrate_counts["$bitrate"]+=count))
            ((archive_files+=count))
        fi
    done
    for year in "${!year_filesize[@]}"; do
        if [ "$year" != "$current_year" ]; then
            ((archive_size+=year_filesize["$year"]))
        fi
    done
    archive_common_bitrate=""
    archive_common_count=0
    for bitrate in "${!archive_bitrate_counts[@]}"; do
        if [ "${archive_bitrate_counts["$bitrate"]}" -gt "$archive_common_count" ]; then
            archive_common_count=${archive_bitrate_counts["$bitrate"]}
            archive_common_bitrate=$bitrate
        fi
    done
    archive_percentage=$(awk "BEGIN { if ($archive_files > 0) printf \"%.2f\", ($archive_common_count/$archive_files)*100; else print \"0.00\" }")
    readable_archive_size=$(numfmt --to=iec --suffix=B --format="%.2f" "$archive_size")
    printf "%-10s %-10s %-15s %-25s %-10s\n" "Archive" "$archive_files" "$readable_archive_size" "$archive_common_bitrate" "${archive_percentage}%"
fi