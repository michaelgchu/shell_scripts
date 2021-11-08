#!/usr/bin/env bash
# Wallpaper Randomizer for Raspberry Pi (LXDE)
# https://github.com/michaelgchu/shell_scripts
##############################################
# Sets a randomly selected image as your background every $delay seconds.
# Designed to be executed on logon, for example by creating a .desktop entry
# in your  ~/.config/autostart  folder.
# Based on a script "Wallz" found in a Raspberry Pi forum thread @
#	https://forums.raspberrypi.com/viewtopic.php?t=254731
# which itself credits
# http://stackoverflow.com/questions/701505/best-way-to-choose-a-random-file-from-a-directory-in-a-shell-script
#########################################
## Script Configuration ##
# Specify the folder containing all your wallpapers (subdirs will get scanned)
dir="$HOME/Pictures"
# Specify the Seconds to wait before switching wallpapers
delay=20

## Main Line ##
# Get a list of all files from $dir -- assume they are all images
list=$(find "$dir" -type f)
test -n "$list" || { echo "You do not have any files in: $dir"; exit 1; }
# Get the item count
count=$(wc -l <<< "$list" )

while true ; do
	# Pick one of the pulled files at random
	pick=$((RANDOM % count + 1))
	filepath=$(sed -n "$pick { p; q}" <<< "$list")
	# Use  pcmanfm  to update the wallpaper
	pcmanfm --set-wallpaper="$filepath"
	sleep $delay
done
