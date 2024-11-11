#!/bin/bash

# Function to replace characters in a string that NTFS forbids from filenames
get_ntfs_safe() {
    local filename=$1
    local replacement_char=$(get_config_value "Local" "replacementChar")
    local new_filename=$(echo "$filename" | sed "s/[\/:*?\"<>|]/$replacement_char/g")
    echo "$new_filename"
}


# Usage: is_absolute_path <path>
#
# Returns 1 if true, 0 if false. Accepts home directory.
is_absolute_path() {
    input="$1"
    if [[ "${input:0:1}" == "/" || "${input:0:1}" == "~" ]]; then
        echo 1
    else
        echo 0
    fi
}

# Usage: read_absolute_path <prompt> <default> <optional>
# 
# <prompt> is passed as -p to read
# <default> is put in [] and returned if the user enters nothing
# <optional> is 1 if the user can enter nothing
#
# Returns the absolute path entered by the user
# Repeats until the user enters a valid absolute path
read_absolute_path() {
    prompt="$1"
    default="$2"
    optional="$3"
    while true; do
        if [[ -z "$default" ]]; then
            read -e -p "$prompt: " input
        else
            read -e -p "$prompt [$default]: " input
            if [[ -z "$input" ]]; then
                input="$default"
            fi
        fi
        if [[ $( is_absolute_path "$input" ) == "1" ]]; then
            echo "$input"
            break
        fi
        if  [[ "$optional" == "1" && -z "$input"  ]]; then
            break
        fi
        echo "Not an absolute path, e.g. /home/user/dir"
    done
}

# Usage: read_d <prompt> [default] [required] [secret]
#
# Read a directory path.
#
# Parameters:
#   prompt: the prompt to display
#   default: the default value
#   TO-DO: required: 1 if the directory must be specified
#   secret: 1 if the directory must be specified but not displayed
read_d() {
    prompt="$1"
    default="$2"
    #required="$3" # not implemented
    secret="$4"

    if  [[ -z  "$default"  ]]; then
        read -p  "$prompt: " input
    else
        if [[ -z "$secret" ]]; then
            read -s -p "$prompt [**NO CHANGE**]: " input
        else
            read -p "$prompt [$default]: " input
        fi
        if  [[ -z  "$input"  ]]; then
            input="$default"
        fi
    fi
    echo "$input"
}

# Usage: choice_1_2 "prompt" "default"
#
# prompt:  prompt to display
# default: default value to use if user enters nothing
#
# Returns: 1 or 2
#
choice_1_2() {
    prompt="$1"
    default="$2"
    while true; do
        if [[ -z "$default" ]]; then
            read -p "$prompt: " input
        else
            read -p "$prompt [$default]: " input
            if [[ -z "$input" ]]; then
                input="$default"
            fi
            break
        fi
        if [[ $input == "1" || $input == "2" ]]; then
            break
        fi
        echo Invalid choice. Must be 1 or 2.
    done
    echo $input
}

# Usage: time_report <seconds>
time_report() {
    secs="$1"

    if [[ $secs -gt 60 ]]; then
        mins=$(($secs / 60))
        if [[ $min  -gt 60 ]]; then
            hours=$(($mins / 60))
            mins=$(($mins % 60))
            echo "Total time: $hours:$mins:$secs"
        else
            echo "Total time: $mins:$secs"
        fi
    else
        if [[ $sec -gt 9 ]]; then
            echo "Done in $secs seconds"
        fi
    fi
    exit 0
}

# Return appropriate piece length for mktorrent
# Maintains mktorrent compatibility for older versions
# Usage: get_piece_length <torrent data>
# Returns: value for -l parameter to mktorrent
get_piece_length() {
    local target="$1"
    local size_kb
    size_kb=$(du -s "$target" | awk '{print $1}')

    if (( size_kb <= 122000 )); then
        echo 16   # 64 k
    elif (( size_kb <= 213000 )); then
        echo 17   # 128
    elif (( size_kb <= 444000 )); then
        echo 18   # 256
    elif (( size_kb <= 922000 )); then
        echo 19   # 512
    elif (( size_kb <= 1870000 )); then
        echo 20   # 1 MB
    elif (( size_kb <= 3880000 )); then
        echo 21   # 2
    elif (( size_kb <= 6700000 )); then
        echo 22   # 4
    elif (( size_kb <= 13900000 )); then
        echo 23   # 8
    else
        echo 24   # 16
    fi
}