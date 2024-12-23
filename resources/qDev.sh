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
# Returns 1 if true, 0 if false. Needs work so it ~~Accepts home directory.~~
is_absolute_path() {
    input="$1"
    #if [[ "${input:0:1}" == "/" || "${input:0:1}" == "~" ]]; then # the ~ is not expanding in cd "$a" when a="~" :-/
    # should be able to find a way to use it though
    if [[ "${input:0:1}" == "/" ]]; then
        echo 1
    else
        echo 0
    fi
}

# Usage: read_absolute_path <prompt> <default> [optional]
# 
# <prompt> is passed as -p to read
# <default> is put in [] and returned if the user enters nothing
# [optional] is 1 if the user can enter nothing, defaults to required
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
        input=$(echo "$input" | sed 's/^"//;s/"$//')
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

# Usage: read_relative_path <prompt> <startDir> [optional]
#
# <prompt> is passed as -p to read
# <startDir> is used in pushd "$startDir" > /dev/null || return so that the
#   user can begin auto-completion from a provided directory
# [optional] is "1" if the user can enter nothing, defaults to required
read_relative_path() {
    prompt="$1"
    startDir="$2"
    optional="$3"
    while true; do
        if [[ -z "$startDir" ]]; then
            read -e -p "$prompt: " input
            input=${input%/}
            input=$(echo "$input" | sed 's/^"//;s/"$//')
        else
            # We'll use pushd and pop so that tab completion happens in the
            # context of the specified start directory
            pushd "$startDir" > /dev/null || return
            echo Tab completion from "$(pwd)" enabled > /dev/tty
            read -e -p "$prompt: " input
            # must remove trailing slash first, if present
            input=${input%/} 
            # then quotes, if present, so we can check it with realpath
            input=$(echo "$input" | sed 's/^"//;s/"$//') 
            if [[ "$( is_absolute_path "$input" )" == "1" ]]; then
                input="$( cd "$input" && pwd )"
            elif [[ -d "$(realpath "$startDir/$input")" ]]; then # it is relative to the pushd $startDir
                echo input=$(cd "$(realpath "$startDir/$input")" && pwd)
                input=$(cd "$(realpath "$startDir/$input")" && pwd)
            fi            
            popd > /dev/null || return
        fi
        if [[ -d "$input" && "$input" != "$startDir" ]]; then
            echo "$input"
            exit 0
        fi
        if  [[ "$optional" == "1" && -z "$input"  ]]; then
            echo ""
            exit 0
        elif [[ -z "$input" ]]; then
            echo "Please specify a directory to target"
        else
            echo "Not a valid path \"$input\""
        fi
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



# Function to resolve the full path of the script, regardless of whether it was
# invoked with a symlink and/or via $PATH
#
# Usage: scriptPath=$(resolve_script_path $0)
resolve_script_path() {
    local script="$1"
    local script_dir

    # If invoked without a path component, search the PATH
    if [[ "$script" != */* ]]; then
        # Use the command 'which' to find the full path in $PATH
        script=$(which "$script") || return 1
    fi

    # Continue resolving to ensure we follow any symlinks
    while [ -h "$script" ]; do
        script_dir=$(dirname -- "$script")
        # Use readlink to read the target of the symlink
        script=$(readlink -- "$script")
        
        # If script was a relative symlink, resolve it relative to the directory of the symlink
        [[ "$script" != /* ]] && script="$script_dir/$script"
    done

    # Return the absolute path
    script_dir=$(dirname -- "$script")
    script=$(cd -P -- "$script_dir" && pwd -P)/$(basename -- "$script")

    echo "$script"
}

# Prints a time summary (silent if < 10 seconds)
# Usage: time_report <seconds>
time_report() {
    secs="$1"

    if [[ $secs -gt 60 ]]; then
        mins=$(( $secs / 60 ))
        secs=$(( $mins & 60 ))
        if [[ $min  -gt 60 ]]; then
            hours=$(( $mins / 60 ))
            mins=$(( $mins % 60 ))
            echo "Total time: $hours:$mins:$secs" > /dev/tty
        else
            echo "Total time: $mins:$secs" > /dev/tty
        fi
    else
        if [[ $sec -gt 9 ]]; then
            echo "Done in $secs seconds" > /dev/tty
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
    elif (( size_kb <= 288000 )); then
        echo 18   # 256
    elif (( size_kb <= 444000 )); then
        echo 19   # 512
    elif (( size_kb <= 922000 )); then
        echo 20   # 1 MB
    elif (( size_kb <= 1870000 )); then
        echo 21   # 2
    elif (( size_kb <= 3880000 )); then
        echo 22   # 4
    elif (( size_kb <= 6700000 )); then
        echo 23   # 8
    elif (( size_kb <= 12300000 )); then
        echo 24   # 32
    else
        echo 25   # 64
    fi
}

# Because sometimes users say 2019-2022 instead of 2019 2022
set_y1_y2() {
    local input="$1"
    y1=""
    y2=""

    # Check if the input contains a hyphen, indicating a range
    if [[ "$input" == *-* ]]; then
        # Split the input on the hyphen
        y1="${input%-*}"
        y2="${input#*-}"

        # Alternatively use IFS and read
        # IFS='-' read -r y1 y2 <<< "$input"
    else
        # Assign directly if input is separate arguments
        y1="$input"
        y2="$2"
    fi
}

# Makes a 600x600 jpg thumbnail if there is a cover.jpg or cover.png available
# $1 - target directory
# $2 - save path
# $3 - thumbnail path (optional override of save path)
make_thumb() {
    local target_directory="$1"
    local savePath="$2"
    local thumbPath="$3"
    local cover

    if [[ -z "$target_directory" ]]; then
        echo "No target directory specified" 1>&2
        exit 1
    fi
    if [[ -z "$savePath" ]]; then
        echo "No save path specified" 1>&2
        exit 1
    fi

    if [[ -f "$target_directory/cover.jpg" ]]; then
        cover="cover.jpg"
    elif [[ -f "$target_directory/cover.png" ]]; then
        cover="cover.png"
    else
        cover=""
    fi

    if [[ ! -z "$cover" ]]; then # make a thumb in the thumb / save path
        if [[ -z "$thumbPath" ]]; then
            convert "$target_directory/$cover" -resize 600x600 "$savePath/cover-$(basename "${target_directory}")-1-1.jpg"
            echo "$savePath/cover-$(basename "${target_directory}")-1-1.jpg"
        else
            convert "$target_directory/$cover" -resize 600x600 "$thumbPath/cover-$(basename "${target_directory}")-1-1.jpg"
            echo "$thumbPath/cover-$(basename "${target_directory}")-1-1.jpg"
        fi
    fi
}
