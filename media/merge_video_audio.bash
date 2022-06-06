#!/bin/bash
SCRIPTNAME='Merge Video and Audio Streams'
LAST_UPDATED='2022-06-05'
# See Usage() function for purpose and calling details
# The resulting call will look something like this:
#	ffmpeg -i VideoSrc.mp4 -i AudioSrc.m4a -map 0:v:0 -map 1:a:0 -c copy output.mp4
#
# Updates
# =======
# 20220605 - cleaned up script
# 20151124 - First working version

Usage()
{
	cat << EOM
Syntax:
   ${0##*/} [options]
Purpose: given 2 media files, create a file that is the combination of the
(1st) video stream from one file and the (1st) audio stream from the other.

The 'ffmpeg' command-line tool is used to perform this stream copying.
This script does not check to see if the output container is suitable.

OPTIONS
=======
   -h    Show this message
   -v 'filename'
         The media file containing the video stream to use
   -a 'filename'
         The media file containing the audio stream to use
   -o 'filename'
         The output file to create
   -y    Do not warn before overwriting existing output file

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

# Test for required tools
which ffmpeg &>/dev/null || { echo "Error: command '$cmd' not present"; exit 1; }

# Process script args/settings
extraArgs='-hide_banner'
while getopts ":hv:a:o:y" OPTION
do
	case $OPTION in
		h) Usage; exit 0 ;;
		v) inV="$OPTARG" ;;
		a) inA="$OPTARG" ;;
		o) outfile="$OPTARG" ;;
		y) extraArgs+=' -y' ;;
		*) echo "${yellow}Warning: ignoring unrecognized option -$OPTARG${normal}" ;;
	esac
done
shift $(($OPTIND-1))

# Check all filenames were provided
echo -n "${yellow}"
test -f "$inV" -a -r "$inV" || { echo 'Must supply a file for video'; exit 1; }
test -f "$inA" -a -r "$inA" || { echo 'Must supply a file for audio'; exit 1; }
test -n "$outfile" || { echo 'Must supply a filename to write to'; exit 1; }
echo -n "${normal}"

# -------------------------------
# Execute the FFmpeg call.  Explanation:
# - supplying the files to process is done via the  -i  arguments; ordering is important
# - the  -map  arguments indicate the stream of the input files that will be used; 
#	- first # is the input file index, starting at 0
#	- next letter indicates video or audio stream type
#	- last # indicates the video/audio stream # within the source file
#	- e.g. "0:v:0"  means use the first file's video stream #0
# - the  '-c copy'  argument means to simply copy the streams w/o re-encoding
# -------------------------------
ffmpeg -i "$inV" -i "$inA" -map 0:v:0 -map 1:a:0 -c copy "$outfile" $extraArgs
exit $?
