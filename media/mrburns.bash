#!/usr/bin/env bash
SCRIPTNAME='Mr (Ken) Burns Image-to-Video'
LAST_UPDATED='2026-04-13'
SCRIPT_AUTHOR="Michael G Chu, https://github.com/michaelgchu/"
# See Usage() function for purpose and calling details, also ExtendedUsage()

set -u

# -------------------------------
# "Constants", Globals / Defaults
# -------------------------------

# These first few variables are default values that can be set via script arguments: fps; seconds; transitionSeconds; crfTemp; crfFinal; ext

# The framerate of the video to produce. ex. 60, 30
fps=60
# The duration in seconds to animate the image (not including the transition, which has no zoom/pan). 7 is a good length for photos with multiple people visible.
seconds=7
# The duration of the fade-in/fade-out transition, as seen once you concatenate 2 of these generated videos together. 0.5 is a good number
transitionSeconds=0.5

# What CRF to use for the x264 encoding. Google AI sez low motion content like animated slideshows can use 18-20 without creating overly huge movie files.
# This is for the intermediate files. Let's use higher quality for these
crfTemp=18
# This one is for the final generated all-combined video slideshow
crfFinal=20

# What media container format to use. Allowed values are 'mp4' and 'mkv'
ext='mp4'

# The resolution of the video to generate.
# Hardcoded to 1920x1080, with no option available to change that (for now)
# NOTE: script has only been tested with 1920x1080
VidRes='1920x1080'

# Options to pass to all calls of FFmpeg:
# -hide_banner : prevent a lot of gunk from appearing at initial call
# -nostdin : prevent errors from FFmpeg trying to get input from stdin
# -loglevel error : only show errors. Using "warning" gives a bit more
stdFFmpegOpts='-hide_banner -nostdin -loglevel error'


# Location to write Output files, ex. prepared movie clips, an entire concatenated slideshow movie.
# Setting to a period (.) means writing the movie files to the same folder as the source images
outputFileLocation=.

# Location to write interim files, ex. frame extracts
tempFolder=/tmp
# If you have a single RAM disk (tmpfs) defined in your /etc/fstab, then that location will be used for temporary files.
if [ $(grep --count -P '^[^#]+\stmpfs\s' /etc/fstab) -eq 1 ] ; then
#	# Get the mount point of the single defined RAMdisk
	# This search pattern should ignore any commented lines
	folderRD=$(awk '/^[^#]/ { if ( $3 == "tmpfs" ) print $2 }' /etc/fstab)
	test -n "$folderRD" && tempFolder="$folderRD"
	echo "TEMP FOLDER IS: --${tempFolder}--"
fi

# Set the filename for the log file to (potentially) create
mylog="runlog-mrburns-$(date +%Y%m%d_%H%M%S).log"

# Listing of all required non-standard tools.  The script will abort if any cannot be found
# (Interestingly, some commands like 'column' are not standard in the Debian image for WSL2)
requiredTools='exiftool ffmpeg ffprobe'


# Prepare some variables for the temporary files we will create
# These are the images and list file, which will always be PNG and .txt no matter what the user chooses.
rotated="$tempFolder/0_prepped.png"	# a replacement image to use if the input has any rotations
frame1="$tempFolder/1a_frame1.png"
frameN="$tempFolder/1b_frameN.png"
list="$tempFolder/list.txt"	# for doing concatenations

# Force definition of $COLUMNS variable via tput
COLUMNS=$(tput cols)

# -------------------------------
# General Functions here
# The meaty stuff is further down, below command-line processing
# These functions make heavy use of global variables, and the ability to affect global variables from within.
# -------------------------------

Usage() {
	cat << EOM | xargs --null echo -ne | fold --spaces --width=${COLUMNS:-80}
\e[1mUsage: ${0##*/} [options] <file/folder to process>\e[0m

This script builds a nice photo slideshow that focuses the viewer's attention on a specific individual for each image.

It generates a "Ken Burns" zoom + pan animation using a supplied photo with face tagging metadata (at least 1 face tagged per image). The video starts with the full image visible and zooms in on the tagged person's face. An optional fade transition leads into and out of the video. The video file is created within the same folder as the image, and is given the same name as the image with '.$ext' added as the new extension.

If an image has multiple faces tagged, the first one is used by default. You can use the -p option to specify the tagname to use instead.

If you provide a folder, this script processes each image contained within it (no subfolders). It will look specifically for these fipe types: .heic .heif .jpg .jpeg png tiff

Existing movie files will NOT be overwritten - if the script finds the file in the output folder, the processing is simply skipped.

In "Build" mode, the script assembles all the prepared movie clips into a single slideshow video. While it defaults to alphabetical by filename, you can customize the order.

All generated videos have a fixed resolution of $VidRes. Other parameters can be configured.

You can run in "Check" mode to just evaluate the image metadata.

A log file is created unless you use the -L option to disable it, i.e. "$mylog"

EOM
cat << EOMOpt | column --table --separator '|' \
	--table-columns Option,Parameter,Description \
	--table-right Option \
	--table-wrap Description
-h||Show this message
-H||Show extended help, ex. on overall process, including basic how-to for facial tagging in digiKam.
-c||Check the input(s) - no videos are created.  Checks if the facial tagging & orientation metadata are OK.
-o|{outputFolder}|Specify the Output folder to store all the generated videos when in the normal processing mode.  By default, it puts them in the input images' folder.
-b|{outputFilePath}|Build the final movie/slideshow. Unlike the other processing modes, you must provide the full path & name of the movie file to create.  ex. "~/final.mp4"
-p|{name}|Zoom in on this provided face tag. Use "RANDOM" to make it randomized per file.
-A||When building the final movie, order the movie clips Alphabetically by filename. (Default)
-R||When building the final movie, Randomize the order of the movie clips.
-f|{fps}|Set the Framerate to use for the generated videos. (Default = $fps)
-a|{seconds}|Set the Ken Burns Animation duration in seconds. Note: this does not change the animation speed! (Default = $seconds)
-t|{seconds}|Set the fade-in/fade-out transition duration in seconds. (Default = $transitionSeconds)
-q|{crf}|Set the CRF Quality for generating the videos. (Default = $crfTemp for the individual animations, $crfFinal for the final slideshow)
-e|mp4/mkv|Set the media file container to produce. Allowed values are "mp4" and "mkv". (Default = $ext)
-n||Do Not prompt before continuing, whether it is informational or warnings
-r||Force Rotations as per metadata. Use this option if the resulting videos show up sideways. (Should only be required for older versions of FFmpeg)
-v||Verbose mode: talk a lot more
-L||Disable Logging
EOMOpt
}

ExtendedUsage() {
# Describe full process, including DigiKam for the face detection & facial recognition.
	cat << EOM | xargs --null echo -ne | fold --spaces --width=${COLUMNS:-80}
For each photo file supplied, this script will create a video file with the following properties (by default):
- $VidRes resolution @ $fps fps
- $(awk -v a=$seconds -v b=$transitionSeconds 'BEGIN { print a + b }') seconds total duration:
	- $seconds seconds of animation
	- $transitionSeconds seconds of transition frames
- Fade-to-white transitions
- x264 video encoding in a .$ext container
	- yuv420p pixel format, to ensure maximum compatibility

It goes through the following steps:
1. Confirm the movie clip hasn't already been created
2. Extract & check that the image's metadata is OK
3. Perform transformations on the face tag metadata if orientation metadata indicates it is required
4. Optionally, force a rotation of the image if it was requested via the -r switch
5. Perform the Ken Burns effect on the image, creating a movie clip
6. Extract the first frame of the animation, then extend it into a movie clip
7. Extract the  last frame of the animation, then extend it into a movie clip
8. Concatenate these 3 movie clips
9. Apply a fade-in/fade-out to the beginning/end of the full movie clip


\e[4mGetting the Tools\e[24m
The 3 non-standard tools required by this script are: exiftool, ffmpeg, ffprobe.

exiftool is a Perl-based metadata reading/writing tool. You can download it from the official website @
https://exiftool.org/install.html
Follow the instructions to either fully install the tool or otherwise make it available for execution.

FFmpeg is a media processing tool and ffprobe can report information about media files. Both should be available in your Linux software repository within a single package. On Debian-based systems, the command to install is: sudo apt install ffmpeg


\e[4mRequired Face Tagging Metadata\e[24m
Each image must have exactly 1 person's face tagged within its metadata. The 2 key data points required are displayed as "Region Area X" and "Region Area Y" when queried using exiftool.

Only 1 face tagging programme has been tested and confirmed to produce image metadata that is compatible with this script: digiKam v8.8.0 (for JPEG files).

Here is some sample output for an image containing a single face tagged as "Pa":
$ exiftool myPhoto.jpg | grep -P 'Region Area [XY]|Region Name'
Region Name                     : Pa
Region Area X                   : 0.186428
Region Area Y                   : 0.259191


\e[4mFace Tagging with digiKam\e[24m
digiKam is a photo management software that can be used for face tagging.  Here is a link directly to the face tagging section of its online documentation: https://docs.digikam.org/en/left_sidebar/people_view.html

This help section attempts to cover the key info you need for performing face detection and People/Face tagging. Some quick basics on digiKam first:
- "People" tags are a special kind of tag that can be applied to a specific area of a photo (a person's face)
- the left-hand side of the window has different tabs that allow you to browse your photo collection in different ways, ex. by Album, by People tag
- a digiKam Album is simply a folder on your computer

Installation:
1. On Debian-based systems, the command to install is: sudo apt install digikam
2. On first run, use the setup wizard to go through the configuration. Most of the default options are okay.
3. Be sure to add your folder with photos as an Album
4. If asked whether digiKam should update image files with metadata, say Yes
5. When asked to install deep-learning models, say Yes. This is necessary to enable to face detection and facial recognition
6. Afer the wizard completes, go to Settings > Configure digiKam > Metadata. Ensure the "Face Tags (including face areas)" checkbox is turned on

Initial Face Detection:
1. Go to Browse > People (or click the "People" label near the bottom left-hand side of the digiKam window)
2. Within the "Search in" tab, select the album(s) to process
3. Click the "Scan for Faces" button to start
4. At the top of the panel, go to People > Unknown. The main region will show all the faces digiKam finds
5. Find the face of the person you want to tag. Hover over their face to display a "Who is this?" prompt. Type in their name and press ENTER. This creates a new Person tag and tags the image.
6. Tag a few additional photos of this person: select 1 or more images of this person's face, then Drag & drop your selections to the new People tag in the upper-left corner of the digiKam window. You can act on multiple images by holding CTRL or SHIFT

Facial Recognition:
After tagging a few images, try the automatic facial recognition feature
1. On the left-hand side, under Scan for Faces > Settings, set Workflow = "Recognize faces only"
2. Click "Scan for Faces" button
3. Minimize the entire "Scan for Faces" section, then click People > Unconfirmed
4. If digiKam correctly identified the face, hover over the face and click the green checkmark. You can use CTRL or SHIFT to confirm multiple images at once.

Forcing Metadata Writing to File:
If you have performed face tagging on an image but this script reports that your image does not have any face tag metadata, then
1. Go to your Album view and select the album/folder with those photos
2. Go to Album > Write Metadata to Files

HEIC Warning:
Even if you only have a single face tagged, HEIC files may have metadata that indicate multiple face regions. The solution is to convert the image to JPEG format.
1. Select the HEIC images from the main region of digiKam's window
2. Go to Item > Add to New Queue. This pops open the Batch Queue Manager
3. within the Control Panel at the bottom right, double-click on Convert > Convert to JPEG
4. within the Tool Settings at the top right, set JPEG quality = 100% and Chroma subsampling = 4:4:4 (best quality)
5. Click "Run" to start the conversion


\e[4mx264 codec, CRF values\e[24m
This script generates movie files using the x264 codec. As part of this, it uses CRF to establish decent quality. x264 allows for CRF values between 0 and 51. 
By default, the script uses a higher quality value of $crfTemp for the individual movie clips it creates, and a slightly lower quality value of $crfFinal for the final concatenated slideshow movie.


\e[4mTemporary Files\e[24m
The script creates several temporary files that keep getting overwritten as it processes individual images.
If your /etc/fstab file has a single RAM Disk entry, then temporary files are written to this location. Otherwise, it writes to /tmp/.
(It will write to: $tempFolder)


\e[4mPossible future enhancements\e[24m
- Allowing photo images to have more than 1 tagged person
	- user can/must specify which person to zoom in on
- custom colour for fade-in/fade-out transitions
- allowing the -n option to bypass more confirmations
- specifying the zoom factor to reach by the end of the animation / specifying the zoom speed
- permanent config file so you don't have to run the script with the same arguments all the time


\e[4mAborting the script while it is processing a folder\e[24m
EOM
	ExplainHowToAbort
	echo "To view this help page-by-page, run a command like so: $0 -H | less -R"
	echo "(Press spacebar, down arrow or PgDn to advance, 'q' to quit)"
}


ExplainHowToAbort() {
# Provide some help on how to break out of this script when it's running in Folder mode.
	cat <<- EOM | fold --spaces --width=${COLUMNS:-80}
	If you need to abort out of this script, first press CTRL-Z and then enter the command "kill %".

EOM
}


# This function will be called on script exit, if required.
finish() {
	# Removing (some) temporary files, logs that are completely empty
	rm -f "$buffer"
	test "$mylog" != /dev/null -a ! -s "$mylog" && rm "$mylog"
	test ! -s "$faillog" && rm "$faillog"
}
buffer=''
faillog=''


showProgress() {
# Display something to show that there's some sort of progress and script is still alive & working
# When Verbose mode is off, just print a dot without moving to new line
# Otherwise, run an ANSI seq echo that returns to column 1, clears the line, then prints what was provided (with "..." added)
# This script assumes it's being run from an ANSI-capable terminal. We could try to test that by running `tput cols`, if we cared to ...
	test $BeVerbose = false && echo -n '.' || echo -en "\e[999D\e[K$* ..."
}


echoUL() {
# Printing with underlines
	echo -e "\e[4m$*\e[0m"
}

echoRed() {
# For showing error messages in Red colour
	echo -e "\e[31m$*\e[0m"
}


log() {
# Writes the given message to the log file, stripping off any ANSI control sequences first
	echo -e "$*" | sed -r 's/\x1b\[[0-9;]+m//g' >> "$mylog"
}

logecho() {
	echo -e "$*"
	log "$*"
}

logechoRed() {
	echoRed "$*"
	log "$*"
}


feedChatty() {
# For Verbose mode, this function adds the provided string to a text variable `chattyMsg` with vertical/horizontal spacing
	chattyMsg+="\t$*\n"
}
# This is what will get printed to console after operations complete for a single file (for single / folder processing)
chattyMsg=''


printTitle() {
	test $# -eq 1 && cmd=echo || cmd=echoUL
	local stringy="$SCRIPTNAME ($LAST_UPDATED)"
	$cmd "${stringy//?/ }"
	$cmd "$stringy"
	echo 
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


IsImageFile() {
# Tests if the provided filepath is for an image. Returns 0/true or non-zero/false
	file --brief "$1" | grep -Pi '\bIMAGE\b' >/dev/null
	return $?
}

setOutputFilepath() {
# For normal Processing mode. Given the filepath (of an input image), print/output the full filepath of the output file to create
	echo "$outputFileLocation/$(basename "$1").$ext"
}


CalculateDurations() {
# Set values to be used for generating the various clips based on other global variables.
# Sets/establishes global variables: duration; halfFade
	# (Need to use awk since we are potentially dealing with decimal numbers)
	# Total duration of the animated image
	duration=$(awk -v a=$fps -v b=$seconds 'BEGIN { printf "%d", a*b}')
	# How many seconds for for the fade-in or fade-out
	halfFade=$(awk -v total=$transitionSeconds 'BEGIN { print total / 2 }')
}

isPositiveInteger() {
# Return true/0 if the provided arg is a positive integer number, ex. 30
	if [[ "$1" =~ ^[0-9]+$ ]] ; then
		return 0
	fi
	return 1
}

isPositiveRealNumber() {
# Return true/0 if the provided arg is a positive real number, ex. 29.97
	if [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]] ; then
		return 0
	fi
	return 1
}

isZero() {
# Return true/0 if the provided arg is effectively zero. ex. 0, 0.0
	if [[ "$1" =~ ^0+(\.0*)?$ ]] ; then
		return 0
	fi
	return 1
}



# ************************************************************
# Reading script args & basic tests
# ************************************************************

printTitle

# Run it right now so we can print things if the user runs Help.
CalculateDurations

args="$*"

# Process script args/settings
BuildMode=false		# true == concatenating the generated movie clips to create the final slideshow video. This mode takes precedence.
CheckMode=false		# false == normal processing mode
DoRotations=false	# true == will force a rotation on the image before animating
DoPause=true		# true == prompt before starting and for warnings
BeVerbose=false		# true == give lots more output to console & log
ConcatRandom=false	# true == randomize movie clip order. false = alphabetically ordered
providedCRF=	# We won't know what mode we're in till we are past this getopts section, so have a buffer variable ready
FaceTag='FIRST'	# which face to zoom in on. Default is first one found
while getopts ":hHco:b:p:ARf:a:t:q:e:nrvL" OPTION
do
	case $OPTION in
		h) Usage; exit 0 ;;
		H) ExtendedUsage; exit 0 ;;
		c) CheckMode=true ;;
		o)
			test -z "$OPTARG" && { echo 'Error: -o requires a folder. Run with -h to see options'; exit 1; }
			# Get the absolute filepath, as we will change directory before processing
			outputFileLocation=$(readlink --canonicalize "$OPTARG") ;;
		b) BuildMode=true
			test -z "$OPTARG" && { echo 'Error: -c requires a filepath for the movie to create. Run with -h to see options'; exit 1; }
			# Confirm provided output filename is either .mp4 or .mkv
			lastbit=${OPTARG##*.}
			ext=${lastbit,,}
			test "$ext" = 'mp4' -o "$ext" = 'mkv' || { echo 'Error: slideshow to create must be .mp4 or .mkv'; exit 1; }
			# Get the absolute filepath, as we will change directory before processing
			SlideshowFilepath=$(readlink --canonicalize "$OPTARG") ;;
		p)
			test -z "$OPTARG" && { echo 'Error: -p requires a face tag Name or "RANDOM" to select one at random. Run with -h to see options'; exit 1; }
			FaceTag="$OPTARG" ;;
		A) ConcatRandom=false ;;
		R) ConcatRandom=true ;;
		f) test -z "$OPTARG" && { echo 'Error: -f requires a framerate. Run with -h to see options'; exit 1; }
			if isZero "$OPTARG" ; then
				echo "Error: -f value cannot be zero"
				exit 1
			fi
			if ! isPositiveRealNumber "$OPTARG" ; then
				echo "Error: '$OPTARG' is not a positive number"
				exit 1
			fi
			fps=$OPTARG
			;;
		a) test -z "$OPTARG" && { echo 'Error: -a requires a time in seconds. Run with -h to see options'; exit 1; }
			if isZero "$OPTARG" ; then
				echo "Error: -a value cannot be zero"
				exit 1
			fi
			if ! isPositiveRealNumber "$OPTARG" ; then
				echo "Error: '$OPTARG' is not a positive number"
				exit 1
			fi
			seconds=$OPTARG
			;;
		t) test -z "$OPTARG" && { echo 'Error: -t requires a framerate. Run with -h to see options'; exit 1; }
			if isZero "$OPTARG" ; then
				transitionSeconds=0
			elif isPositiveRealNumber "$OPTARG" ; then
				transitionSeconds=$OPTARG
			else
				echo "Error: '$OPTARG' is not a number"
				exit 1
			fi
			;;
		q) test -z "$OPTARG" && { echo 'Error: -q requires a CRF number. Run with -h to see options'; exit 1; }
			# CRF for x264 can go from 0 - 51 inclusive
			if isPositiveInteger "$OPTARG" ; then
				test $OPTARG -le 51 || { echo 'Error: CRF must be from 0 to 51'; exit 1; }
				providedCRF=$OPTARG
			else
				echo "Error: '$OPTARG' is not an integer"
				exit 1
			fi
			;;
		e) test -z "$OPTARG" && { echo 'Error: -e requires a container extension. Run with -h to see options'; exit 1; }
			if [ "$OPTARG" = 'mp4' ] ; then
				ext='mp4'
			elif [ "$OPTARG" = 'mkv' ] ; then
				ext='mkv'
			else
				echo "Error: '$OPTARG' is not a supported extension"
				exit 1
			fi
			;;
		n) DoPause=false ;;
		r) DoRotations=true ;;
		v) BeVerbose=true ;;
		L) mylog=/dev/null ;; # any logging goes to nothingness
		*) echo "Warning: ignoring unrecognized option -$OPTARG" ;;
	esac
done
shift $(($OPTIND-1))

## Make the =~ bash operator case insensitive.
## Note: cannot do this before the getopts, as it prevents case detection
#shopt -s nocasematch

# Test for all required tools/resources
flagCmdsOK='yes'
for cmd in $requiredTools
do
	hash $cmd &>/dev/null || { echoRed "Error: command '$cmd' not present"; flagCmdsOK=false; }
done
# Abort if anything is missing
test $flagCmdsOK = 'yes' || { echoRed "Run with -H to read about Getting the Tools"; exit 1; }

# This script must be called with a single file / folder to work with (for any of the 3 modes)
test $# -eq 1 || { echo 'You must provide a single file or folder to work with. Run with -h to get help.'; exit 0; }
test -e "$1" || { echo "Error: '$1' does not exist. Run with -h to get help."; exit 1; }
if [ -d "$1" ] ; then
	givenWut='folder'
	inputLocation=$1
elif [ -f "$1" ] ; then
	givenWut='file'
	inputLocation=$(dirname "$1")
else
	echo "Error: '$1' is neither a file nor a folder. Run with -h to get help."
	exit 1
fi

# It's a trap! ... to help with cleanup
trap finish EXIT

# Set the rest of the variables for our temporary files, now that we have processed the commandline arguments.
baseVid="$tempFolder/0_animated.$ext"
videoIn="$tempFolder/2a_intro_clip.$ext"
videoOut="$tempFolder/2b_outro_clip.$ext"
videoPenultimate="$tempFolder/3_before_fade.$ext"

# If logging is enabled, Ensure we can write to the script's log file
# Also, switch the variable to use absolute filepath, as we change directory for Folder processing
touch "$mylog" || { echo "Error: cannot write to log file '$mylog'. Aborting"; exit 1; }
mylog=$(readlink --canonicalize "$mylog")

buffer=$(mktemp) || { echo 'Error: could not create buffer file'; exit 1; }
faillog=$(mktemp) || { echo "Error creating temporary file"; exit 1; }

# Recalculate durations and such now that we've received input from user
CalculateDurations

# Set the output location for normal processing mode
if [ "$outputFileLocation" = . ] ; then
	# Using default behaviour of creating output files within input folder
	outputFileLocation=$(readlink --canonicalize "$inputLocation")
fi
# If we're in Build mode, replace with the output path that was provided.
test $BuildMode = 'true' && outputFileLocation=$(dirname "$SlideshowFilepath")

# If we aren't in Check mode, ensure we can write to the output location
if [ $CheckMode != 'true' ] ; then
	test -d "$outputFileLocation" || { echoRed "Error: '$outputFileLocation' is not a folder or does not exist"; exit 1; }
	test -w "$outputFileLocation" || { echoRed "Error: '$outputFileLocation' is not writable"; exit 1; }
fi

# Replace a CRF value, if it was provided on command line
if [ -n "$providedCRF" ] ; then
	if [ $BuildMode = 'true' ] ; then
		crfFinal=$providedCRF
	else
		crfTemp=$providedCRF
	fi
fi

printTitle 'to-log' > "$mylog"
echo "Log for run on:  $(date)" >> "$mylog"

cat << EOL | tee -a "$mylog"
Call Summary
------------
EOL
# Coding note: newer versions of column can specify --output-width unlimited
cat << EOM2 | column --table --output-width ${COLUMNS:-80} --separator : --output-separator ' : ' --table-wrap 2 | tee -a "$mylog"
Executed in dir:$(pwd)
Arguments:$args
Provided ($givenWut):$1
Face:$FaceTag$(test "$FaceTag" = FIRST -o "$FaceTag" = RANDOM && echo ' face tag found')
Mode:$(
	test $BuildMode = 'true' && echo -e "Build Slideshow movie -> $SlideshowFilepath\nClip Order:$(test $ConcatRandom = 'true' && echo 'Random' || echo 'Alphabetical')" ||
	( test $CheckMode = 'true' && echo 'Check Metadata (facial tagging & orientation)' ||
	echo -e "Process Images to Video\nOutput Location:$outputFileLocation" ) )
Container (ext):$ext
Framerate:$fps
Animation time:$seconds
Transition time:$(test $transitionSeconds = '0' && echo 'N/A' || echo $transitionSeconds)
CRF:$(test $BuildMode = 'true' && echo $crfFinal || ( test $CheckMode = 'true' && echo 'N/A' || echo $crfTemp ) )
Force Rotations:$DoRotations
Temporary files:$tempFolder
Logging to:$mylog

EOM2

if $DoPause ; then
	echo "Press ENTER to continue, or CTRL-C to cancel"
	read
fi



# -------------------------------
# Task-heavy Functions here
# All the image checking, processing, etc etc
# These functions make heavy use of global variables, and the ability to affect global variables from within.
# -------------------------------

yoinkTagValues() {
# Searches through the content of the $metadata variable for the given
# metadata tag and returns its comma-separated values as 1 entry per line.
# ex. the tag 'Region Name                     : Ma, Pa' is returned as:
#		Ma
#		Pa
	test $# -eq 1 || { echo 'ERROR with call to yoinkTagValues()'; exit 1; }
	perl -ne "if ( /^$1\s+:/ ) {
		s/.*?://;
		s/^\s*|\s*$//g;
		s/, /\n/g;
		print
	}" <<< $metadata
}

ExtractImageMetadata() {
# Extract specific image metadata from the supplied image file. The values get saved to multiple global variables.
# Face Tagging fields can have 1 value per person; these data are stored in global associative arrays.
# The first value from each Face Tag field is also assigned to a normal global var, as convenience.
# No testing is done here, besides basic checks that values were obtained.
# Return true on success, false if there were problems using the metadata extraction tool.
	unset rNames aaRType aaRAX aaRAY aaRAUnit RT RAX RAY RAU
	local rv
	# The $metadata var is global so we can call a helper fcn
	metadata=$(exiftool "$1")
	test -z "$metadata" && { feedChatty 'Metadata fail'; return 1; }

	# Simple extractions first: what is required for rotations
	orientation=$(<<< "$metadata" grep -P '^Orientation'  | cut -f2 -d: | sed -r 's/^\s+//')
	imgWidth=$(   <<< "$metadata" grep -P '^Image Width'  | cut -f2 -d: | tr -d [:space:])
	imgHeight=$(  <<< "$metadata" grep -P '^Image Height' | cut -f2 -d: | tr -d [:space:])

	# We expect Region Name to potentially have spaces. Not sure what that would look like. Also not sure what it would look like if there was a comma!
	# The rest of the metadata tags should not have spaces in the values

	# Extract Region Type first to grab record count, as the values should be simple 
	rv=$(yoinkTagValues 'Region Type')
	test -z "$rv" && { feedChatty 'Metadata fail - Region Type missing'; return 1; }
	# Determine the total # of tags we have by splitting on the separators
	tagCount=$(wc -l <<< $rv)
	feedChatty "Image has $tagCount value(s) per Face Tag"
	# Extract all the Names and store in a normal 0-indexed array
	rv=$(yoinkTagValues 'Region Name')
	declare -a rNames
	for ((i = 1; i <= tagCount; i++)) ; do
		rNames+=($(sed -n "$i {p;q}" <<< $rv))
	done

	# Now push all the Region Type values into a global associative array
	declare -g -A aaRType aaRAX aaRAY aaRAUnit
	rv=$(yoinkTagValues 'Region Type')
	for ((i = 1; i <= tagCount; i++)) ; do
		aaRType[${rNames[$i-1]}]=$(sed -n "$i {p;q}" <<< $rv)
	done
	# And then the rest of the Face tags
	rv=$(yoinkTagValues 'Region Area X')
	test -z "$rv" && { feedChatty 'Metadata fail - Region Area X missing'; return 1; }
	for ((i = 1; i <= tagCount; i++)) ; do
		aaRAX[${rNames[$i-1]}]=$(sed -n "$i {p;q}" <<< $rv)
	done
	rv=$(yoinkTagValues 'Region Area Y')
	test -z "$rv" && { feedChatty 'Metadata fail - Region Area Y missing'; return 1; }
	for ((i = 1; i <= tagCount; i++)) ; do
		aaRAY[${rNames[$i-1]}]=$(sed -n "$i {p;q}" <<< $rv)
	done
	rv=$(yoinkTagValues 'Region Area Unit')
	test -z "$rv" && { feedChatty 'Metadata fail - Region Area Unit missing'; return 1; }
	for ((i = 1; i <= tagCount; i++)) ; do
		aaRAUnit[${rNames[$i-1]}]=$(sed -n "$i {p;q}" <<< $rv)
	done
	# Finally, assign the first value set to scalar globals.
	RT=${aaRType[$rNames]}
	RAX=${aaRAX[$rNames]}
	RAY=${aaRAY[$rNames]}
	RAU=${aaRAUnit[$rNames]}

	# Dump out face tag data
	if [ $BeVerbose = 'true' ] ; then
		local dump=$((echo -e 'Region Name\tRegion Type\tRegion Area X\tRegion Area Y\tRegion Area Unit'
		for x in ${!aaRType[@]}; do
		echo -e "$x\t${aaRType[$x]}\t${aaRAX[$x]}\t${aaRAY[$x]}\t${aaRAUnit[$x]}"
		done) | column --table --separator $'\t' | sed '2,$ { s/^/\t/ }')
		feedChatty "$dump"
	fi
}

GetImgMetadata() {
# Given an image filepath and a face tag name / placeholder, this fcn extracts
# image metadata from the file and then tests it.
# Parameters:
# 1) the filepath of the image
# 2) the face tag Name or placeholder
#	If given a Name, then this name will be searched for using a straight text match.
#	If "FIRST" is given, then the first Name found will be selected, and its related values will be tested.
#	If "RANDOM" is given, then all Face metadata is extracted first and a random one gets selected for testing.
# The following items are tested:
# - confirming image dimensions were retrieved
# - confirming "Orientation" value is understood, and image dimensions support it
# These tests will be against that selected face tag:
# - confirming "Region Type" = "Face" and "Region Area Unit" = "normalized" for the given Face
# - confirming "Region Area X" and "Region Area Y" are present
# Tests everything. Prints to console and log right here (except for the chatty bits)
# Returns 0/true on pass, 1/fail if metadata is missing or problematic.
	local retcode=0
	test $# -eq 2 || { echo 'ERROR: Bad call!'; exit 1; }
	# Perform the metadata extraction - return immediately if there was a problem
	ExtractImageMetadata "$1" || return 1

	# Face selection: either use the first set (already assigned), or pick one using $2, or make it random
	if [ "$2" != 'FIRST' ] ; then
		if [ "$2" = 'RANDOM' ] ; then
			# will pick a face at random
			FaceName=$(printf "%s\n" "${!aaRType[@]}" | shuf -n 1)
		else
			FaceName="$2"
		fi
		feedChatty "Face tag selected: $FaceName"
		RT=${aaRType[$FaceName]:=FACE TAG NAME NOT FOUND IN IMAGE}
		if [ "$RT" = 'FACE TAG NAME NOT FOUND IN IMAGE' ] ; then
			logechoRed "Error: provided face tag name not found in image metadata"
			feedChatty "Face '$FaceName' not found in image"
			return 1
		fi
		RAX=${aaRAX[$FaceName]}
		RAY=${aaRAY[$FaceName]}
		RAU=${aaRAUnit[$FaceName]}
	fi

	# Test that the facial tagging metadata is good
	if [ "$RT" != 'Face' ] ; then
		logechoRed "Error: metadata tag 'Region Type' is not 'Face'"
		feedChatty "Region Type is not 'Face'"
		retcode=1
	fi
	if [ "$RAU" != 'normalized' ] ; then
		logechoRed "Error: metadata tag 'Region Area Unit' is not 'normalized'"
		feedChatty "Region Area Unit is not 'normalized'"
		retcode=1
	fi

	if [ -n "$RAX" -a -n "$RAY" ] ; then
		if [ -z "$(tr -d .[:digit:] <<< $RAX$RAY)" ] ; then
			feedChatty "Region Area: $RAX,$RAY"
		else
			logechoRed 'Error: Region Area X/Y is not a single number each'
			feedChatty 'Multiple values for Region Area X/Y'
			retcode=1
		fi
	else
		logechoRed "Error: no 'Region Area X/Y' metadata in image"
		feedChatty 'No Region Area X/Y metadata'
		retcode=1
	fi

	# Test we have the basic dimension data
	if [ -n "$imgWidth" -a -n "$imgHeight" ] ; then
		feedChatty "Dimensions: $imgWidth x $imgHeight"
	else
		logechoRed "Error: missing image width / height metadata in image"
		feedChatty 'No image dimension metadata'
		retcode=1
	fi

	# Test if the image has any rotation metadata. If it does, we must pre-process the image file
	# Rotations involve transposing the image data, and also modifying the facial tag X & Y positions.
	# We cannot handle all rotations at this time (no sample files to test with) - for any rotation we aren't handling, we abort
	if [ "$orientation" = "" -o "$orientation" = 'Horizontal (normal)' ] ; then
		: # OK: regular / no rotation
		feedChatty "Orientation metadata: '$orientation'"
	elif [ "$orientation" = 'Rotate 90 CW' -a $imgWidth -gt $imgHeight ] ; then
		: # OK: Portrait image to force re-orient
		feedChatty "Orientation metadata: '$orientation'"
	elif [ "$orientation" = 'Rotate 180' -a $imgWidth -gt $imgHeight ] ; then
		: # OK: Upside-down landscape image to force re-orient
		feedChatty "Orientation metadata: '$orientation'"
	else
		logechoRed "Error: don't know how to handle '$orientation' orientation metadata in image"
		feedChatty "Orientation metadata: '$orientation'"
		retcode=1
	fi

	return $retcode
}


mustRotateImg() {
# Return true if the previously-extracted image metadata indicates that we must perform a rotation
	if [ "$orientation" = "" -o "$orientation" = 'Horizontal (normal)' ] ; then
		# NO PROBLEM with rotation/orientation
		return 1
	elif [ "$orientation" = 'Rotate 90 CW' -a $imgWidth -gt $imgHeight ] ; then
		# Portrait image to force re-orient
		return 0
	elif [ "$orientation" = 'Rotate 180' -a $imgWidth -gt $imgHeight ] ; then
		# Upside-down landscape image to force re-orient
		return 0
	else
		echoRed "Error: don't know how to handle '$orientation' orientation metadata in image"
		exit 1
	fi
}

S0_RotateImage() {
# Performs 2 separate & distinct actions on the supplied image:
# 1. Manipulate the extracted face tagging coordinates. This is always required if the image has rotation metadata
# 2. If requested, also force the rotation of the image. This is necessary if FFmpeg doesn't respect the metadata
# Writes output image to filepath in var `rotated` (whether rotation is actually done or not)
	local buf
	test -z "$1" && { echo 'BAD CALL'; exit 1; }
	showProgress 'Rotating image'
	if [ "$orientation" = 'Rotate 90 CW' -a $imgWidth -gt $imgHeight ] ; then
		#echo Portrait image to force re-orient
		if [ $DoRotations = true ] ; then
			ffmpeg $stdFFmpegOpts -i "$1" -vf "transpose=1" -map_metadata -1 "$rotated" -y
			test $? -ne 0 && return 1
			feedChatty 'Forced rotation of image 90 degrees'
		else
			cp "$1" "$rotated"
		fi
		buf=$RAX
		RAX=$RAY
		RAX=$(awk -v var=$RAX 'BEGIN { print 1 - var }')
		RAY=$buf
		feedChatty 'Manipulated face coordinates for 90 degree rotation'
	elif [ "$orientation" = 'Rotate 180' -a $imgWidth -gt $imgHeight ] ; then
		#echo Upside-down landscape image to force re-orient
		if [ $DoRotations = true ] ; then
			ffmpeg $stdFFmpegOpts -i "$1" -vf "transpose=1,transpose=1" -map_metadata -1 "$rotated" -y
			test $? -ne 0 && return 1
			feedChatty 'Forced rotation of image 180 degrees'
		else
			cp "$1" "$rotated"
		fi
		RAX=$(awk -v var=$RAX 'BEGIN { print 1 - var }')
		RAY=$(awk -v var=$RAY 'BEGIN { print 1 - var }')
		feedChatty 'Manipulated face coordinates for 180 degree rotation'
	fi
}

S1_DoMrBurns() {
# Perform the animated 'Ken Burns' zoom & pan on the provided image, creating an interim movie file.
# This is the most complicated action in the entire script. There are 3 steps, all handled by a 
# single complex FFmpeg call: Pad > Scale > Ken Burns animation
# To make things easier to read, we use local variables here to store all the FFmpeg parameters
	test $# -eq 1 || { echo 'BAD CALL'; exit 1; }
	showProgress 'Creating Ken Burns animation'
	# This 'pad' argument forces the image to be a landscape 16:9
	# To prevent issues, we apply ceil() to force even numbers for the dimensions.
	local pad='pad=width=ceil(max(iw\,ih*(16/9))/2)*2:height=ceil(max(ih\,iw/(16/9))/2)*2:x=(ow-iw)/2:y=(oh-ih)/2:color=black'
	# We do upscaling mostly to reduce the jitter in the animation.
	# This 'scale' argument increases the image to 8000 pixels wide, and the corresponding height to match existing aspect ratio. The -2 means to ensure this height is divisible by 2
	# Note: this assumes we aren't working with super-super-high resolution photos that exceed 8000 pixels wide.
	# ... guessing it would work very poorly if we do this, in fact, effectively downscaling and having jitter
	local scale='scale=8000:-2'
	# This 'zoompan' argument is where the magic happens. It generates the Ken Burns animation, starting from the fully visible image and zooming & panning over time.
	# Breakdown of the zoompan entries:
	# z='min(zoom+0.001,1.5)' : increases the zoom level by 0.001 per frame until it reaches a maximum of 1.5x the initial (scaled) size.
	# x=...:y=... : calculate the x and y coordinates per frame. By applying the face tag region area (RAX:RAY), we get FFmpeg to focus on the person.
	# s=$VidRes : Specifies the output video resolution
	# d=$duration : Sets the duration in frames
	# fps=$fps : sets the framerate
	local zoom="zoompan=z='min(zoom+0.001,1.5)':x='(iw-iw/zoom)*$RAX':y='(ih-ih/zoom)*$RAY':s=$VidRes:d=$duration:fps=$fps"
	# Run the FFmpeg command to generate the animated zoom & pan video
	ffmpeg $stdFFmpegOpts -loop 1 -i "$inputImg" -vf "$pad,$scale,$zoom" -t $seconds -c:v libx264 -crf $crfTemp -pix_fmt yuv420p "$baseVid" -y
}

ExtractFirstFrame() {
# Extracts the first frame from our interim $baseVid video file and saves as $frame1 . Super small fcn, here for consistency
# No arguments taken.
	ffmpeg $stdFFmpegOpts -i "$baseVid" -frames:v 1 "$frame1" -y
	return $?
}

ExtractLastFrame() {
# Extracts the last frame from our interim $baseVid video file and saves as $frameN
# Aborts if we cannot probe the interim video. But just returns false if it fails to extract
# No arguments taken.
	# Get the frame count of our generated video file
	local N=$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -of csv=p=0 "$baseVid")
	test -n "$N" || { echoRed "Error: could not get # of frames from '$baseVid"; exit 1; }
	# ... and reduce by 1 for 0-index
	N=$((N - 1))
	# Extract the last frame using this frame number
	ffmpeg $stdFFmpegOpts -i "$baseVid" -vf "select='eq(n,$N)'" -vframes 1 "$frameN" -y
	return $?
}

S2_Frame2FrozenVideo() {
# Extracts the specified frame from the interim $baseVid movie file, then extends it into a freeze-framed video.
# Apply a duration based on the Transition duration global variable
# Arg 1:  'first' or 'last' 
# Builds $videoIn or $videoOut
	local innie outie
	showProgress "Extracting $1 frame"
	if [ "$1" = 'first' ] ; then
		ExtractFirstFrame || return 1
		innie="$frame1" ; outie="$videoIn"
	elif [ "$1" = 'last' ] ; then
		ExtractLastFrame || return 1
		innie="$frameN" ; outie="$videoOut"
	else
		echo 'BAD CALL'; exit 1;
	fi
	showProgress "Extending frame for transition video"
	ffmpeg $stdFFmpegOpts -loop 1 -framerate $fps -t $halfFade -i "$innie" -c:v libx264 -tune stillimage -crf $crfTemp -pix_fmt yuv420p "$outie" -y
	return $?
}

PrepareInterimConcatList() {
# Create the concatenation list to combine the Mr Burns video with the 2 transition video clips
	cat > "$list" << EOD
	file '$videoIn'
	file '$baseVid'
	file '$videoOut'
EOD
	test $? -eq 0 || { echoRed  "ERROR: could not write to $list"; exit 1; }
}

S3_Concat3InterimVideos() {
# Concatenate the 3 videos together, saving to output file $videoPenultimate
# Does straight stream copy stitching to save on time, because the expectation is a full re-encode will happen in Build mode.
# Takes no arguments
	showProgress "Concatenating all 3 pieces"
	ffmpeg $stdFFmpegOpts -f concat -safe 0 -i "$list"  -c copy "$videoPenultimate" -y
	return $?
}


S4_ApplyFadeInFadeOut() {
# Applies the final step to have a completed single clip: the fade-in at start and fade-out at end
# Arg 1: name of the final output video file to produce
	test $# -eq 1 || { echo 'BAD CALL'; exit 1; }
	showProgress 'Applying transition'
	# Get the duration of the new video
	DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$videoPenultimate" )
	test -n "$DUR" || { echored "Error: could not get duration of intermediate file '$videoPenultimate'"; return 1; }
	# Then reduce that time by half the transition time
	DUR=$(awk -v base=$DUR 'BEGIN { print base - $halfFade }')
	# Now perform the fade-in and fade-out in these added spots
	ffmpeg $stdFFmpegOpts -i "$videoPenultimate" \
		-vf "fade=t=in:st=0:d=$halfFade:color=white, fade=t=out:st=$DUR:d=$halfFade:color=white" \
		-c:v libx264 -crf $crfTemp -pix_fmt yuv420p "$1" -y
	return $?
}


BuildMovieClipFromImage() {
# Creates a complete animated movie file from the provided image, with a fade-in and fade-out if the user hasn't disabled that (by requesting 0 seconds for transition time)
# Durations based on global vars. Uses stream copy to concatenate, because it is not truly meant as a final file. 
# Arg 1: the input filepath
# Arg 2: the output video filepath
# Requirements: the fcn  PrepareInterimConcatList()  must be executed first, if we are creating transitions
	test $# -eq 2 || { echo 'BAD CALL'; exit 1; }
	# Start with the metadata extraction & testing. End early if problems
	showProgress 'Extracting metadata'
	GetImgMetadata "$1" "$FaceTag" || return 1
	# Check if image needs to be rotated. If so, do it, and adjust filepath vars
	if mustRotateImg ; then
		S0_RotateImage "$1" || { logechoRed 'Error while rotating!'; return 1; }
		inputImg="$rotated"
	else
		# no need to rotate the input image
		inputImg="$1"
	fi

	# Generate the Ken Burns animation (outputs to `baseVid`)
	S1_DoMrBurns "$inputImg" || { logechoRed 'Error while generating animation!'; return 1; }
	if [ $transitionSeconds = 0 ] ; then
		# No transitions requested, so we are done!
		cp "$baseVid" "$2" || { logechoRed 'Error copying animation file to destination!'; return 1; }
		return 0
	fi
	# Getting to this point means we follow the remaining steps to handle the fade-in/out
	# Generate a lead-in placeholder video from frame 1
	S2_Frame2FrozenVideo 'first' || { logechoRed 'Error building lead-in video!'; return 1; }
	# Generate a lead-in placeholder video from the last frame
	S2_Frame2FrozenVideo 'last' || { logechoRed 'Error building lead-out video!'; return 1; }
	# Concatenate the 3 prepared interim video files now into a penultimate file
	S3_Concat3InterimVideos || { logechoRed 'Error concatenating the interim video files!'; return 1; }
	# Finally, apply the fade-in/fade-out transition
	S4_ApplyFadeInFadeOut "$2" || { logechoRed 'Error applying fade-in/fade-out transitions!'; return 1; }
	return 0
}

folderBMCFI() {
# The helper to call within the Folder processing loop. It builds the output filename, and if the file already exists it exits early. Otherwise it runs the Build function.
# Requires  PrepareInterimConcatList()  to be executed already, if we are creating transitions
# Skipping counts as success
# Returns false only on error.
	test $# -eq 1 || { echo 'BAD CALL'; exit 1; }
	# Build output filepath based on script settings and input filename
	finalFile=$(setOutputFilepath "$1")
	# Confirm the destination output file does not already exist
	test -e "$finalFile" && { logecho "Skip - output exists: '$finalFile'"; return 0; }
	# Perform the entire processing suite, including the metadata testing
	BuildMovieClipFromImage "$1" "$finalFile"
	return $?
}


PrepareSlideshowList() {
# Given the folder containing the individual video clips to concatenate,
# create the concatenation list and then require user to press ENTER to continue
# Will abort if something went wrong
# Looks for any files with .mp4 or .mkv extensions - all is allowed since we are using full re-encoding.
	local sortOpt sortDesc
	if [ $ConcatRandom = 'true' ] ; then
		sortOpt='--random-sort'
		sortDesc='randomized'
	else
		sortOpt=''
		sortDesc='alphabetical'
	fi
	find "$(readlink --canonicalize "$1")" -maxdepth 1 -type f -regextype posix-extended -iregex '.*\.(mp4|mkv)$' | sort $sortOpt | sed -r "s/.*/file '&'/" > "$list"
	test $? -eq 0 || { logechoRed  "ERROR: could not write to $list"; exit 1; }
	test -s "$list" || { logechoRed "Error: no movie clips found in this folder"; exit 1; }

	cat << EOM
The list of $(wc -l < "$list") videos in $sortDesc order is here:
$list
If you want, you can edit the list text file now to adjust the ordering.
(Do not change the formatting of any line - just move them around.)

EOM
	read -p 'Press ENTER when you are ready to continue with the concatenation ' lolwut
}


MakeSlideshow() {
# Stitches together the video files stored in the `$list` fie listing, writing to a single final movie file `$SlideshowFilepath`. Full re-encoding.
# (Will never allow for simple stream-copy, because even VLC cannot play that properly!)
	# Full re-encode, to prevent glitchiness from media players when dealing with a massive list of concatenated movies
	# ... the +faststart is supposed to add some extra processing to enhance compatibility of the final movie file
	local opts=$stdFFmpegOpts
	# If verbose mode is on, do not limit the output of FFmpeg as it runs the re-encode on the whole set of movie clips.
	test $BeVerbose = 'true' && opts='-hide_banner -nostdin'
	# Execute FFmpeg with the time shell keyword so we can easily get the time to execute afterwards.
	time ffmpeg $opts -f concat -safe 0 -i "$list" -c:v libx264 -crf $crfFinal -pix_fmt yuv420p -preset medium -movflags +faststart "$SlideshowFilepath" -y
	return $?
}


# ************************************************************
# Main Line - Single File Portion
# This short section handles when a single input file was provided.
# The script terminates regardless of outcome.
# 2 modes can be done: Check or Process.
# ************************************************************

if [ $givenWut = 'file' ] ; then
	# Script called to work with a single image file.
	if ! IsImageFile "$1" ; then
		logechoRed "Error: '$1' is not an image file"
		exit 1
	fi
	if [ $CheckMode = 'true' ] ; then
		# In Check Mode, just extract & test the image metadata
		GetImgMetadata "$1" "$FaceTag"; rv=$?
		# Only need to print an OK message on success, because fails will get 1+ error messages displayed
		test $rv -eq 0 && logecho "Metadata scan OK"
		# Spit out all our chatty messages when in verbose mode
		test $BeVerbose = true && logecho "$chattyMsg"
		exit $rv
	fi
	# Getting to this point means we are in Process Mode.
	# Build output filepath based on script settings and input filename
	finalFile=$(setOutputFilepath "$1")
	# Confirm the destination output file does not already exist
	test -e "$finalFile" && { logecho "Skip - output exists: '$finalFile'"; exit 0; }
	# Record when we start
	startDT="$(date)"
	logecho "Image File Processing begins at: $startDT"
	# Prepare a file we'll need for the last step - assuming we are building transitions
	test $transitionSeconds != 0 && PrepareInterimConcatList	# this aborts script on failure
	# Perform the entire processing suite, including the metadata testing
	BuildMovieClipFromImage "$1" "$finalFile" ; rv=$?
	test $rv -eq 0 && logecho "OK"
	# Spit out all our chatty messages when in verbose mode
	test $BeVerbose = true && logecho "$chattyMsg"
	# Capture end time
	endDT="$(date)"
	cat << EOM | tee -a "$mylog"

Processing ends at:   $endDT
Execution duration:   $(secondsToHHMMSS `diffSeconds "$startDT" "$endDT"` )
EOM
	exit $rv
fi


# ************************************************************
# Main Line - Build Mode
# This section handles when we are creating the final slideshow movie.
# ************************************************************

if [ $BuildMode = 'true' ] ; then
	# Perform a quick check: If the target path matches source, then Confirm with user that this is intentional
	outDir=$(dirname "$SlideshowFilepath")
	if [ "$(readlink --canonicalize "$outDir")" = "$(readlink --canonicalize "$1")" ] ; then
		echoRed "WARNING: Final slideshow will be created in your clip folder!"
		echo -e "You've asked to create the final slideshow video within the same folder that your individual animated clips are located. Are you sure you want to do that?\n"
		read -p 'Press ENTER to continue, or CTRL-C to cancel now' confirm
	fi
	# Also confirm they are good to overwrite, if it already exists
	if [ -e "$SlideshowFilepath" ] ; then
		echoRed "WARNING: a file with this exact filepath already exists!"
		read -p 'Press ENTER to continue and overwrite it, or CTRL-C to cancel now' confirm
	fi

	# Generate the concatenation text file, pausing to allow user to re-order if desired
	PrepareSlideshowList "$1"
	# Make it
	MakeSlideshow ; rv=$?
	test $rv -eq 0 && logecho "\nDone. Your slideshow is at: $SlideshowFilepath" || logecho '\nFailure'
	exit $rv
fi


# ************************************************************
# Main Line - Folder Portion
# This section handles when a folder was provided. (For the other 2 scenarios, we would have ended the script already.)
# 2 modes can be done: Check or Process.
# ************************************************************

ExplainHowToAbort

# Enter the folder, to make the calls and such easier
cd "$1"

startDT="$(date)"
logecho "Folder Processing begins at: $startDT"

total_items=$( find . -maxdepth 1 -type f -regextype posix-extended -iregex '.*\.(hei[cf]|jpe?g|png|tiff?)$' | wc -l )
echo $total_items items in this provided folder.

if [ $CheckMode = 'true' ] ; then
	helper=GetImgMetadata
	sayOnOkFile='Metadata scan OK'	# only need to define the on-OK, because fails will get loads of messages displayed
	labelTallyOK='images have OK metadata'
	labelTallyError='images have missing or problematic metadata'
else
	helper=folderBMCFI
	sayOnOkFile='OK/skip'
	labelTallyOK='images processed (or skipped)'
	labelTallyError='images could not be processed'
	# Prepare a file we'll need for the last step of the movie file builds
	PrepareInterimConcatList	# this aborts script on failure
fi

# For Check & Process modes, Iterate through each file in the given folder
itemNum=0
tallyOK=0
tallyError=0
while IFS= read -r -d '' fp
do
	# var (re)sets
	RAX= ; RAY= ; orientation= ; chattyMsg=
	itemNum=$((itemNum + 1))
	echo -en "[$itemNum/$total_items]\t$fp\t" | tee -a "$mylog"
	if ! IsImageFile "$fp" ; then
		# Only count if this is an image
		logecho "Skip: not an image"
	else
		test $BeVerbose = true && echo # Jump to newline if we are chatty so the messages don't overwrite the name of the file being processed
		# execute the check/processing on this file
		if [ $CheckMode = 'true' ] ; then
			GetImgMetadata "$fp" "$FaceTag"
		else
			folderBMCFI "$fp"
		fi
		if [ $? -eq 0 ] ; then
			logecho "$sayOnOkFile"
			tallyOK=$((tallyOK + 1))
		else
			echo "$fp" >> "$faillog"
			tallyError=$((tallyError + 1))
		fi
		# Spit out all our chatty messages when in verbose mode
		test $BeVerbose = true && logecho "$chattyMsg"
	fi
done < <(find . -maxdepth 1 -type f -regextype posix-extended -iregex '.*\.(hei[cf]|jpe?g|png|tiff?)$' -printf '%f\0') # Can't sort since it's null-terminated

# ------------------------------------------------------------
# Final Actions of Main Line - Folder Portion
# ------------------------------------------------------------

endDT="$(date)"

cat << EOM | tee -a "$mylog"

Processing ends at:   $endDT
Execution duration:   $(secondsToHHMMSS `diffSeconds "$startDT" "$endDT"` )

$tallyOK $labelTallyOK
$tallyError $labelTallyError
$((tallyOK + tallyError)) total images found.
$( test $tallyError -gt 0 && logecho "\nFiles that failed are also listed here: $faillog" )
EOM

test $tallyError -eq 0 -a $CheckMode = 'true' && logecho '\nRecommended next step: create the video clips by running this script again without the -c flag.'
test $tallyError -eq 0 -a $CheckMode = 'false' && logecho '\nRecommended next step: play the individual movie clips. If all looks good, build the final slideshow movie by running this script using the -b flag.'

test $tallyError -ne 0 && exit 1 || exit 0

#EOF
