#!/usr/bin/env bash
SCRIPTNAME='GameMaker Gamepad Prep for Linux/Raspberry Pi OS'
LAST_UPDATED='2022-03-27'
# Author: Michael Chu, https://github.com/michaelgchu/
# See Usage() for purpose and call details
#
# Updates
# =======
# 20220327
# - First version

#-------------------------------------------------------------------------------
# Default values / Config settings
#-------------------------------------------------------------------------------
# These are the pre-determined mappings for  $gamepad_name
# Check these references for how to get the mappings for your own devices:
# https://www.reddit.com/r/riskofrain/comments/2mqvub/linux_game_controllers_risk_of_rain/
# https://steamcommunity.com/app/221410/discussions/0/558748653738497361/
gamepad_name='Logitech F310 gamepad'
evdev_absmap='ABS_X=X1,ABS_Y=Y1,ABS_Z=X2,ABS_RZ=Y2'
evdev_keymap='BTN_THUMB=A,BTN_THUMB2=B,BTN_TRIGGER=X,BTN_TOP=Y,BTN_TOP2=LB,BTN_PINKIE=RB,BTN_BASE=LT,BTN_BASE2=RT,BTN_BASE4=START,BTN_BASE3=BACK,BTN_BASE5=TL,BTN_BASE6=TR'
axismap='-y1=y1'

# -----------------------------------------------------------------
# General Functions
# -----------------------------------------------------------------

Usage()
{
	cat << EOM
Usage: ${0##*/} [options]

Runs the  xboxdrv  software for every gamepad you have plugged in so that you
can play Risk of Rain or other GameMaker game on your Linux/Raspberry Pi OS.
The script steps are as follows:
- figure out how many gamepads are plugged in
- run  xboxdrv  for each of those, using the hardcoded mappings/definitions at
  the top of this script
- reorganize the /dev/input/js* files, so your GameMaker game sees the xboxdrv
  ones starting at js0

Normally, the script will end there and  xboxdrv  will continue running.  If
you add the -r option, it will then:
- wait for you to finish playing your game
- shut down all the running  xboxdrv  instances
- revert the changes made to  /dev/input/js*

NOTES:
1) All the gamepads should be the same type - the script assumes they are
2) Two-player Risk of Rain on a RPi4B is actually pretty slow (~ 30fps)

OPTIONS
-------
   -h    Show this message
   -r    Revert the  /dev/input/  changes after you are done gaming

EOM
}

#-------------------------------------------------------------------------------
# Prepare for displaying terminal colours
# https://unix.stackexchange.com/questions/9957/how-to-check-if-bash-can-print-colors
#-------------------------------------------------------------------------------
if [ "$(tput colors)" -ge 8 ]; then
	bold="$(tput bold)"   ; underline="$(tput smul)" ; italics="$(tput sitm)"
	red="$(tput setaf 1)" ; yellow="$(tput setaf 3)"
	green="$(tput setaf 2)" ; blue="$(tput setaf 4)"
	normal="$(tput sgr0)"
fi

#-------------------------------------------------------------------------------
# Argument & Tool check
#-------------------------------------------------------------------------------
echo "${underline}$SCRIPTNAME ($LAST_UPDATED)${normal}"

# Process script args/settings
revert=no
while getopts ":hr" OPTION
do
	case $OPTION in
		h) Usage; exit 0 ;;
		r) revert=yes ;;
		*) echo "${yellow}Warning: ignoring unrecognized option -$OPTARG${normal}" ;;
	esac
done
shift $(($OPTIND-1))

pre_cmd_4_revert=''
if [ $revert = 'yes' ] ; then
	pre_cmd_4_revert='nohup'
fi

# Check that all required tools are available
hash xboxdrv &>/dev/null || { echo "${red}Error: command 'xboxdrv' not present.${normal} Possible source: 'xboxdrv' package"; exit 1; }

#-------------------------------------------------------------------------------
# Begin Main Line - determine how many joysticks we can see in /dev/input/by-id/
# Each  *-event-joystick  maps to an eventX entry in /dev/input/, and is what
# we must supply to xboxdrv as the --evdev argument
#-------------------------------------------------------------------------------
hits=$(find /dev/input/ -regextype posix-extended -regex '/dev/input/js[0-9]+')
if [ -z "$hits" ] ; then
	echo "${yellow}No gamepads found. Plug in all the gamepads you want to use first and then run this script again.${normal}"
	exit 1
fi
hits_count=$(echo "$hits" | wc -l)

echo 'Gamepads found:'
# This array will store the /dev/input/by-id/ entries as keys, and the
# corresponding /dev/input/jsX files they relate to.
declare -A js
while read entry
do
	shortname=${entry##*/}
	shortname=${shortname%%-event-joystick}
	device=$(readlink --canonicalize ${entry/-event-/-})
	echo -e "\t$device == $shortname"
	# Store to array
	js[$entry]=$device
done <<< $(find /dev/input/by-id/ -name '*-event-joystick')

detected=${#js[@]}
test $detected -gt 0 || { echo "${yellow}No gamepads found! Aborting${normal}"; exit 1; }
test $detected -eq $hits_count || { echo "${yellow}Gamepad count does not match listing output! Aborting${normal}"; exit 1; }

cat <<- EOM
	${detected} gamepads found, which ought to be of type: ${bold}$gamepad_name${normal}
	
	We are ready to prepare them for playing GameMaker games, e.g. Risk of Rain

	The following actions will be taken:
	1) Run  xboxdrv  for each of the detected gamepads, which will create new  /dev/input/jsX  entries
	2) Use sudo powers to rename all the  /dev/input/jsX  entries so that the  xboxdrv  ones are recognized by your game
	$(test $revert = 'yes' && echo "3) Wait for you to finish gaming, then undo the renames")

	${green}When you are ready, press ENTER and follow the prompts${normal}
	If you don't want to do this now, press CTRL-C to cancel
EOM
read confirm

# -----------------------------------------------------------------
# Take actions
# -----------------------------------------------------------------

# It would be nice if we could simply delete all the existing /dev/input/js*
# entries, so that the  xboxdrv  ones would start at  /dev/input/js0  but that
# does not work -- not even if we wait 10 seconds after deleting all the files

# Run  xboxdrv  for each gamepad we found
echo -e "\n${bold}Step 1: background-launch  xboxdrv  for each gamepad found${normal}"
# We need to capture all the PIDs
pidlist=''
for eventID in ${!js[@]}
do
	$pre_cmd_4_revert xboxdrv \
		--evdev $eventID \
		--evdev-absmap $evdev_absmap \
		--evdev-keymap $evdev_keymap \
		--axismap $axismap \
		--mimic-xpad \
		--silent &
	pidlist="$pidlist $!"
	sleep 1
done
echo -e "\n${blue}Launched the following processes: ${pidlist}${normal}"

# And then we must do all the renames and such
echo -e "\n${bold}Step 2: reorganize the  /dev/input/js*  files ${underline}(using sudo)${normal}"
# First we rename the original devices with .bak extension
for device in ${!js[@]}
do
	sudo mv --verbose "${js[$device]}" "${js[$device]}.bak"
done
# Next we create symlink replacements for them that point to the ones powered by  xboxdrv
num_to_assign=0
find /dev/input/ -regextype posix-extended -regex '/dev/input/js[0-9]+' |
while read devXboxdrv
do
	sudo ln --verbose --symbolic "$devXboxdrv" "/dev/input/js${num_to_assign}"
	num_to_assign=$((num_to_assign + 1))
done

echo -e "\n${bold}${green}Step 3: Play!${normal}"

# We can stop here if the user does not care about reverting the /dev/input/ folder
if [ $revert = 'no' ] ; then
	echo "Have fun!"
	exit
fi

# Now we wait ...
echo -e "${bold}When you are done, come back here to stop the  xboxdrv  processes${normal}\n"
read -p 'Press ENTER to continue'
# NOTE: xboxdrv will still shutdown even if user presses CTRL-C to cancel here

# And now we finish up
echo -e "\n${bold}Step 4: cleanup${normal}"
echo "Stopping  xboxdr ..."
kill $pidlist
sleep 3

# Now we restore the js* entries simply by replacing the symlinks with the originals
for device in ${!js[@]}
do
	sudo mv --verbose ${js[$device]}.bak ${js[$device]}
done

echo -e "\nAll done. Bye-bye!"
#EOF
