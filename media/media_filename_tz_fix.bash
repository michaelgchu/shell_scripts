#!/usr/bin/env bash
SCRIPTNAME='Media DateTime-Filename Timezone Fixer'
LAST_UPDATED='2025-01-05'
SCRIPT_AUTHOR="Michael G Chu, https://github.com/michaelgchu/"
# See Usage() function for purpose and calling details
#
# The commands used are basically:
#	tzselect : to get home & visiting timezones
#	find : to identify files to process, if none were explicitly provided
#	perl : to extract date and time from a filename, plus separators
#	date : to determine correct name to apply to the file
#
# Updates (noteworthy)
# ====================
# 20250105: first version

# -------------------------------
# "Constants", Globals / Defaults
# -------------------------------

mylog="runlog-timezonefix-$(date +%Y%m%d_%H%M%S).log"


# -------------------------------
# General Functions
# -------------------------------

Usage()
{
	printTitle
	cat << EOM
Usage: ${0##*/}  [options]  [file(s) to process]

Use this script when you have photos/videos from a trip where you
a) were in a different timezone from your home timezone
b) did not change the timezone on your smartphone
For example, if you live in Canada and visited Europe, then your photo file
might be named
	20241104_031351.jpg (3am)
but it should be
	20241104_081351.jpg (8am)

Files must be named as: YYYYMMDD_HHMMSS.ext
Some variations are allowed, like having dashes between the date parts.
ex. YYYY-MM-DD_HH-MM-SS.ext

You can supply filenames to process on the command line. If none provided, the
script will scan the current folder and subfolders. Do not give folder names.
Files will get renamed on the spot. While overwrites are prevented, take care
not to run the script more than once on the same file.

A log file is created, i.e. "$mylog"

OPTIONS
=======
   -h    Show this message
   -c    Only process files in current folder, not any subfolders
   -n    Do not prompt before continuing
   -t    Test only - show what will be done but do not actually rename
   -H TZ -> set your home timezone, ex. "America/Toronto". Defaults to \$TZ
   -V TZ -> set the visited timezone, ex. "Europe/Lisbon"

EOM
}


# This function will be called on script exit, if required.
finish() {
	# Removing temporary files
	rm -f "$buffer"
}
buffer=''


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
RestrictSearch=false	# false == search entire folder tree
DoPause=true		# true == prompt before starting
TestMode=false		# false == do rename files
HomeTZ=$TZ              # initialize to environment's $TZ
VisitTZ=                # initialize
while getopts ":hcCntH:V:" OPTION
do
	case $OPTION in
		h) Usage; exit 0 ;;
		c) RestrictSearch=true ;;
		C) CheckMode=true ;;
		n) DoPause=false ;;
		t) TestMode=true ;;
		H) HomeTZ="$OPTARG" ;;
		V) VisitTZ="$OPTARG" ;;
		*)
			echo -e "\033[31mWarning: ignoring unrecognized option -$OPTARG \033[0m"
			log "Warning: ignoring unrecognized option -$OPTARG" ;;
	esac
done
shift $(($OPTIND-1))

if $RestrictSearch ; then
	findOptions='-maxdepth 1'
else
	findOptions=''
fi

printTitle
date

# It's a trap! ... to help with cleanup
trap finish EXIT

buffer=$(mktemp) || { echo 'Error: could not create buffer file'; exit 1; }

# See if user has provided specific files to process
if [ $# -gt 0 ] ; then
	providedFiles=0
	while [ $# -gt 0 ]
	do
		if [ -e "$1" ] ; then
			if [ -f "$1" ] ; then
				if [ -r "$1" ] ; then
					echo "$1" >> "$buffer"
					providedFiles=$((providedFiles + 1))
				else
					logecho "Note: '$1' is not readable; ignoring"
				fi
			else
				logecho "Note: '$1' is not a file; ignoring"
			fi
		else
			logecho "Note: '$1' does not exist; ignoring"
		fi
		shift
	done
	test $providedFiles -gt 0 || { echo "Error - none of the supplied command line arguments are files. Aborting"; exit 1; }
	SearchingForFiles=false
else
	SearchingForFiles=true
fi

# Get both timezones, if required
if [ -z "$HomeTZ" -o -z "$VisitTZ" ] ; then
	if [ -z "$HomeTZ" ] ; then
		echo -e "\n\033[1mHome Timezone\033[0m not established. Obtaining now ..."
		HomeTZ=$(tzselect)
		test -n "$HomeTZ" || { echo 'No timezone provided. Aborting'; exit 1; }
	fi
	if [ -z "$VisitTZ" ] ; then
		echo -e "\n\033[1mVisited Timezone\033[0m not provided. Obtaining now ..."
		VisitTZ=$(tzselect)
		test -n "$VisitTZ" || { echo 'No timezone provided. Aborting'; exit 1; }
	fi
fi

# Prepare the call summary to display and write to log
msg=$(cat << EOL

Call Summary
------------
Executed in dir  : $(pwd)
Arguments        : $args
Files to process : $(
	if $SearchingForFiles ; then
		test $RestrictSearch = true && echo 'searching current folder' || echo 'searching current folder & subfolders'
	else
		echo
		cat -n "$buffer" | sed -r 's/^/\t/'
	fi
)
Test Mode        : $TestMode $(
	if $TestMode ; then
		echo " - files will not be renamed"
	fi
)
Home Timezone    : $HomeTZ
Visited Timezone : $VisitTZ
EOL
)
echo -e "$msg"

if $DoPause ; then
	echo
	read -p "Press ENTER to continue, or CTRL-C to cancel "
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


Set_Dir_Name_Ext()
{
	if [[ "$1" == *"/"* ]] ; then
		string="$1"
	else
		# no directory, so inject ./
		string="./$1"
	fi
	# Sets these values from the provided filepath
	dir=${string%/*}
	fullname=${string##*/}
	name=${fullname%.*}
	ext=${string##*.}
}


Build_Filepath()
{
	# Build out the full filepath for naming
	echo "${1}/${2}.${3}"
}


# We are now ready to export the Visited Timezone, so the  date  command will perform the conversion for us
export TZ="$VisitTZ"

# Main Loop to process all files
while read filepath
do
	test -z "$filepath" && continue
	echo -en "\nInspecting file '$filepath' "
	Set_Dir_Name_Ext "$filepath"	# set dir, name, ext

	# Extract the date+time out of the filename
	rv=$(perl -ne '
	if (
/^                     # match start of file name
(\d{4})                # capture 4-digit year
(.?)                   # capture date separator as a single character, or nothing
(0[1-9]|1[0-2])        # capture 2-digit month as 01 -> 12
\2                     # match observed date separator
(0[1-9]|[12]\d|3[01])  # capture 2-digit day of month as 01 -> 31
(.*)                   # capture content between date & time
([01]\d|2[0-3])        # capture 2-digit hour as 00 -> 23
(.?)                   # capture time separator as a single character, or nothing
([0-5]\d)              # capture 2-digit minute as 00 -> 59
\7                     # match observed time separator
([0-5]\d)              # capture 2-digit second as 00 -> 59
$                      # match end of file name
/x ) {
		print "Dsep=$2\n";
		print "D=$1-$3-$4\n";
		print "S=$5\n";
		print "Tsep=$7\n";
		print "T=$6:$8:$9\n"; }' <<< "$name")

	if [ -z "$rv" ] ; then
		echo "-Could not grab date & time out. Skipping"
		log "$filepath : SKIP.  Reason: Could not extract date & time from filename"
		tallySkip=$((tallySkip+1))
		continue
	fi
	echo OK
	# Evaluate the perl output to set the shell variables
	eval $rv
	# Use the  date  command to determine new filename to set, matching to file's original convention
	newName=$(date --date="TZ=\"$HomeTZ\" $D $T" "+%Y${Dsep}%m${Dsep}%d${S}%H${Tsep}%M${Tsep}%S")
	newFilepath="$dir/${newName}.${ext}"

	if $TestMode ; then
		logecho "mv --no-clobber --verbose \"$filepath\"\t\"$newFilepath\""
	else
		if [ -e "$newFilepath" ] ; then
			msg="$filepath: SKIP.  Reason: file '$newFilepath' already exists"
			cmp "$filepath" "$newFilepath" >/dev/null
			test $? -eq 0 && msg="${msg}, and they are identical" || msg="${msg}, but they are different"
			logecho "$msg"
			tallySkip=$((tallySkip+1))
		else
			mv --no-clobber --verbose "$filepath" "$newFilepath" 2>&1 | tee -a "$mylog"
			test ${PIPESTATUS[0]} -eq 0 && tallyOK=$((tallyOK+1)) || tallyError=$((tallyError+1))
		fi
	fi

done <<- FILE_LISTING
$(	# Supply filenames to the loop, one per line. Either via the 'find' command, or from the prepared text file
	if $SearchingForFiles ; then
		# Assign a regex to find JPEG, HEIC and MP4/MOV files
		find . $findOptions -regextype posix-extended \
			-iregex '.*(jpe?g|heic|mp4|mov)$'
	else
		cat "$buffer"
	fi
)
FILE_LISTING

# Remove the TZ setting
unset TZ

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
