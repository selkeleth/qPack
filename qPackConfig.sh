#!/bin/bash

configFile="$HOME/.qPack_config"
scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"/resources
source "${scriptDir}/qDev.sh"

# Function to read previous config value with a default option for use with configuration tool
get_config_value_d() {
    local section="$1"
    local key="$2"
    local default_value="$3"
    local value=""
    if [[ -f "$configFile" ]]; then
        value=$(awk -F '=' '/\['"$section"'\]/{a=1} a==1&&$1~/'"$key"'/{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}' "$configFile")
    fi
    echo "${value:-$default_value}"
}


cat <<EOF
*****************************
This script will guide you through the configuration of qPack. Tab completion
is enabled. Nothing will be saved or overwritten until the end. 

The minimum you must know: (^C out if you don't)
- The full path to your podcast media files
- The full path where you want your torrent data files
- Whether you want to make hardlinks or copies
- Your announce URL

NON-AUDIOBOOKSHELF USERS ONLY:
You should also know the keys for the season number, episode number, and release
date. These are the keys that qPack uses via mediainfo on mp3's.

SEEDBOX USERS ONLY:
In addition to user and server, you will need
- The full path to your torrent data files (for auto-sync)
- The full path to your torrent client's .watch folder (optional)
EOF

# Default values
default_mediaPath="$(get_config_value_d 'Local' 'mediaPath')"
default_savePath="$HOME/qPack/output"
savePath=$(get_config_value_d 'Local' 'savePath')
default_savePath="${savePath:-$default_savePath}"
default_thumbPath="$(get_config_value_d 'Local' 'thumbPath')"
default_torrentDataPath="$HOME/torrents/podcasts"
torrentDataPath=$(get_config_value_d 'Local' 'torrentDataPath')
default_torrentDataPath=${torrentDataPath:-$default_torrentDataPath}
default_lnOrCp=$(get_config_value_d 'Local' 'lnOrCp')
default_errorLogPath="$HOME/qPack/"

default_seedUser="$(get_config_value_d 'Seedbox' 'seedUser')"
default_seedServer="$(get_config_value_d 'Seedbox' 'seedServer')"
default_seedPath="$(get_config_value_d 'Seedbox' 'seedPath')"
default_watchPath="$(get_config_value_d 'Seedbox' 'watchPath')"

default_announceUrl="$(get_config_value_d 'Tracker' 'announceUrl')"

default_seriesTag="Part/Position"
seriesTag=$(get_config_value_d 'Tags' 'seriesTag')
default_seriesTag=${seriesTag:-$default_seriesTag}
default_episodeTag="series-part"
episodeTag=$(get_config_value_d 'Tags' 'episodeTag')
default_episodeTag=${episodeTag:-$default_episodeTag}
default_dateTag="releasedate"
dateTag=$(get_config_value_d 'Tags' 'dateTag')
default_dateTag=${dateTag:-$default_dateTag}

# Get local preferences
echo
echo Enter the full path to your media files.
echo Audiobookshelf users will find this in their podcast library settings
mediaPath="$(read_absolute_path "Enter media path" "$default_mediaPath" | tail -n 1)"
echo
echo Enter the full path to the directory where qPack will save .torrent files
savePath="$(read_absolute_path "Enter save path" "$default_savePath" | tail -n 1)"
echo
echo Thumbnails qPack makes when a source is available will be saved there unless you
echo enter a different path below.
thumbPath="$(read_absolute_path "Enter thumb path" "$thumbPath" 1 | tail -n 1)"
echo
echo "If your podcast media are stored on the same volume as your torrent"
echo "data files, you may prefer to hardlink the torrent files instead of"
echo "copying them. Which tool should qPack use when creating torrents from"
echo "from your media files?"
echo
echo 1\) Use ln to create hardlinks to the original media files
echo 2\) Use cp to make copies of the files
lnOrCp="$(choice_1_2 "Enter 1 or 2" "$default_lnOrCp" | tail -n 1)"
echo
echo "What is the full path to your torrent data files?"
torrentDataPath="$(read_absolute_path "Torrent data" "$default_torrentDataPath" | tail -n 1)"
echo "Where should success and error log files be made?"
errorLogPath="$(read_absolute_path "Error logs" "$default_errorLogPath" | tail -n 1)"
echo
echo "****** YOUR SAVED DEFAULT HAS NOT BEEN LOADED ******"
echo "Some files may contain characters such as : that must be removed or replaced" 
echo "You may enter a replacement character such as _ or leave blank to delete them"
echo "****** YOUR SAVED DEFAULT HAS NOT BEEN LOADED ******"
read -p "Replacement character [deletion]: " replacementChar
echo
echo "qPack can rsync data files to your seedbox as it packs up torrents."
echo "qPack optionally uploads .torrent files to a seedbox torrent watch directory."
echo "It is up to you to use ssh-copy-id or otherwise set up passwordless ssh for rsync."
echo "Begin this section by entering the seedbox username below."
echo
echo "If you are not a seedbox user, leave blank to skip."
echo "If you have an existing configuration to delete, enter * instead of enter"
seedUser=$(read_d "Seedbox username" "$default_seedUser" | tail -n 1)

if [[ -n "$seedUser" ]]; then
    if [[ "$seedUser" == "*" ]]; then
        seedUser=""
        seedServer=""
        seedPath=""
    else
        echo "Enter the FQDN of your seedbox, e.g. myseedbox.com"
        seedServer=$(read_d "Server FQDN" "$default_seedServer" | tail -n 1)
        echo
        seedPath="$(read_absolute_path "Seedbox data folder" "$default_seedPath" | tail -n 1)"
        echo "If you would like the .torrent file put into a client watch directory, enter the full path to that directory below."
        watchPath="$(read_absolute_path "Watch directory" "$default_watchPath" 1 | tail -n 1)"
    fi
fi

echo
echo "Paste in your personal announce URL. This is on your upload page"
echo "It will be something like https://trackerurl.eq/announce/secret-key"
announceUrl="$(read_d "Announce URL" "$default_announceUrl" | tail -n 1)"

echo
echo "You can customize where mediainfo should look for particular metadata here."
echo "The default tags work for Audiobookshelf users."
echo "If your season, episode, or release dates are not pulling, this may be why."
echo "Run mediainfo on a file to browse what tags are available."
echo
seriesTag="$(read_d "Series tag" "$default_seriesTag" | tail -n 1)"
episodeTag="$(read_d "Episode tag" "$default_episodeTag" | tail -n 1)"
dateTag="$(read_d "Release date tag" "$default_dateTag" | tail -n 1)"

# Remove any trailing / from the path inputs
mediaPath="${mediaPath%/}"
savePath="${savePath%/}"
thumbPath="${thumbPath%/}"
torrentDataPath="${torrentDataPath%/}"
seedPath="${seedPath%/}"
watchPath="${watchPath%/}"
errorLogPath="${errorLogPath%/}"

# Save configurations into the file
cat <<EOF > "$configFile"
[Local]
mediaPath = $mediaPath
savePath = $savePath
thumbPath = $thumbPath

torrentDataPath = $torrentDataPath
errorLogPath = $errorLogPath
lnOrCp = $lnOrCp
replacementChar = $replacementChar

[Seedbox]
seedUser = $seedUser
seedServer = $seedServer
seedPath = $seedPath
watchPath = $watchPath

[Tracker]
announceUrl = $announceUrl

[Tags]
seriesTag = $seriesTag
episodeTag = $episodeTag
dateTag = $dateTag

EOF

cat <<EOF
****************************
qPack configuration complete
****************************

qPack is ready to run! 

There are also a number of useful CLI tools available. 

To see your CLI options, run:
qPack --advanced-help

You can re-run qPackConfig or edit ~/.qPack_config directly
EOF

exit 0