#!/usr/bin/env bash
SCRIPTNAME='10 Minute Timer'
LAST_UPDATED='2025-09-13'
SCRIPT_AUTHOR="Michael G Chu, https://github.com/michaelgchu/"
# See Usage() function for purpose and calling details

set -eu

# -------------------------------
# "Constants", Globals
# -------------------------------
min=10
myInstructions=/tmp/$USER-x_min_timer

# -------------------------------
# Functions
# -------------------------------

Usage()
{
	cat << EOM
$SCRIPTNAME ($LAST_UPDATED)

Usage: ${0##*/} [options]

Sleeps for $min minutes (by default), then displays a "toast" popup
notification to indicate the time is up.
Running this script again before the timer runs out will add additional time.

The popup is done using the  notify-send  command, which requires a
notification daemon. The "Dunst" package offers that.

OPTIONS
=======
-h    Show this message
-t #  Sleep for the provided # of minutes instead of the default $min

EOM
}

# -------------------------------
# Main Line
# -------------------------------
while getopts ":ht:" OPTION
do
	case $OPTION in
		h) Usage; exit 0 ;;
		t) min="$OPTARG" ;;
		*) echo "Warning: ignoring unrecognized option -$OPTARG" ;;
	esac
done
shift $(($OPTIND-1))

test -z "$(tr -d [:digit:] <<< $min)" || { echo 'Error: -t requires an integer'; exit 1; }

# If file already exists, then a timer is still in place. Add to it and quit
if [ -e $myInstructions ] ; then
	notify-send --urgency=low 'Timer Extend' "Extending timer by $min minutes"
	echo $min >> $myInstructions
	exit 0
fi

# Record the minutes to an "instructions" file
echo $min > $myInstructions
trap 'rm --force $myInstructions' EXIT

# Do the initial toast, in part to let the user know what it'll look like
notify-send --urgency=low 'Timer Start' "Timer starting for $min minutes"

# Begin main loop: read through each recorded number in sequence
total=0
while read amount
do
	total=$((total + amount))
	sleep $((amount * 60))
done < $myInstructions

notify-send --wait "Time's Up" "${total} minutes have passed"
#EOF
