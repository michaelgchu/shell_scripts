#!/usr/bin/env bash
SCRIPTNAME='Undo Media Renamer Script'
LAST_UPDATED='2025-01-05'
SCRIPT_AUTHOR="Michael G Chu, https://github.com/michaelgchu/"
# See Usage() function for purpose and calling details
#
# Updates (noteworthy)
# ====================
# 20250105: first version

# -------------------------------
# "Constants", Globals / Defaults
# -------------------------------

mylog="runlog-undo_rename-$(date +%Y%m%d_%H%M%S).log"


# -------------------------------
# General Functions
# -------------------------------

Usage()
{
	printTitle
	cat << EOM
Usage: ${0##*/}  [options]  logFile

Use this script if you ran one of the renaming scripts and have to undo those
name changes. (Ex.  media_filename_tz_fix.bash; media_renamer.bash)

It will read the provided log file and basically reverse what it sees
Ex. when it sees this line in the log:
	renamed './20230129_191605.jpg' -> './2023-01-29_19-16-05.jpg'
it will run this:
	mv -vi './2023-01-29_19-16-05.jpg' './20230129_191605.jpg' 

A log file is created, i.e. "$mylog"

OPTIONS
=======
   -h    Show this message
   -n    Do not prompt before continuing
   -t    Test only - show what will be done but do not actually rename

EOM
}



diffSeconds()
{
# Provide the difference between earlier date/time $1 and second date/time $2 in seconds
	s_starttime=$(date --date="$1" +%s)
	s_endtime=$(date --date="$2" +%s)
	echo $((s_endtime - s_starttime))
}

secondsToHHMMSS()
{
# Given a time in seconds, output as HH:MM:SS
	date --date="1970-01-01 + $1 seconds" +%H:%M:%S
}


log()
{
# Writes the given message to the log file
        echo -e "$*" >> "$mylog"
}

logecho()
{
        echo -e "$*" | tee -a "$mylog"
}

printTitle()
{
	title="$SCRIPTNAME ($LAST_UPDATED)"
	echo "$title"
	printf "%0.s-" $(seq 1 ${#title})
	echo 
}

# ************************************************************
# Reading script args & basic tests
# ************************************************************

args="$*"

# Process script args/settings
DoPause=true		# true == prompt before starting
TestMode=false		# false == do rename files
while getopts ":hnt" OPTION
do
	case $OPTION in
		h) Usage; exit 0 ;;
		n) DoPause=false ;;
		t) TestMode=true ;;
		*)
			echo -e "\033[31mWarning: ignoring unrecognized option -$OPTARG \033[0m"
			log "Warning: ignoring unrecognized option -$OPTARG" ;;
	esac
done
shift $(($OPTIND-1))

printTitle
date

# Test that user has provided exactly 1 log file to process
test $# -eq 1 || { echo "You must supply a script logfile to process"; exit 1; }
test -e "$1" || { echo "Provided '$1' does not exist"; exit 1; }
test -f "$1" || { echo "Provided '$1' is not a file"; exit 1; }
test -r "$1" || { echo "Provided '$1' is not readable"; exit 1; }

msg=$(cat << EOL

Call Summary
------------
Executed in dir  : $(pwd)
Arguments        : $args
Log to process   : $1
Test Mode        : $TestMode $(
	if $TestMode ; then
		echo " - files will not be renamed"
	fi
)
EOL
)
echo -e "$msg"

if $DoPause ; then
	echo -e "\nPress ENTER to continue, or CTRL-C to cancel"
	read
fi

# Ensure we can write to the script's basic log file
touch "$mylog" || { echo "Error: cannot write to log file '$mylog'. Aborting"; exit 1; }
printTitle > "$mylog"
echo "Log for run on:  $(date)" >> "$mylog"
echo -e "$msg" >> "$mylog"


# ************************************************************
# Main Line
# Define a few functions and then get going
# ************************************************************

tallyOK=0
tallyError=0
tallySkip=0

startDT="$(date)"
logecho "Processing begins at: $startDT"


# Main Loop to process all files
while read logline
do
	rv=$(perl -ne "
	if (
/^renamed\s+           # match start of line
('[^']+')              # capture entire original filename, including quotes
\s+->\s+               # skip the in between
('[^']+')              # capture entire renamed filename, including quotes
$                      # match end of line
/x )"' {
		print "got=$2\n";
		print "want=$1\n"; }' <<< "$logline")

	if [ -z "$rv" ] ; then
		echo "-Could not grab date & time out. Skipping"
		log "$logline : SKIP.  Reason: Could not acquire the 2 names from line"
		tallySkip=$((tallySkip+1))
		continue
	fi
	# Evaluate the perl output to set the shell variables
	eval $rv
	# Use the  date  command to determine new filename to set, matching to file's original convention

	if $TestMode ; then
		logecho "mv --no-clobber --verbose \"$got\"\t\"$want\""
	else
		logecho time to do the thing
		if [ -e "$want" ] ; then
			msg="$logline: SKIP.  Reason: file '$want' already exists"
			cmp "$got" "$want" >/dev/null
			test $? -eq 0 && msg="${msg}, and they are identical" || msg="${msg}, but they are different"
			logecho "$msg"
			tallySkip=$((tallySkip+1))
		else
			mv --no-clobber --verbose "$got" "$want" 2>&1 | tee -a "$mylog"
			test ${PIPESTATUS[0]} -eq 0 && tallyOK=$((tallyOK+1)) || tallyError=$((tallyError+1))
		fi
	fi

done <<- FILE_LISTING
$(	# Yank out just the rename lines, for full processing within the loop
	grep -P '^renamed' "$1"
)
FILE_LISTING

endDT="$(date)"

cat << END_SUMMARY | tee -a "$mylog"

Processing ends at:   $endDT
Execution duration:   $(secondsToHHMMSS `diffSeconds "$startDT" "$endDT"` )

Run summary:
- OK:    $tallyOK
- Error: $tallyError
- Skip:  $tallySkip

Log file generated: $mylog
END_SUMMARY

if [ $tallyError -ne 0 -o $tallySkip -ne 0 ] ; then
	exit 1
else
	exit 0
fi

#EOF
