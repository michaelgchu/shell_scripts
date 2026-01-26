#!/usr/bin/env bash
SCRIPTNAME='Full/Incremental Backup Creation Script plus Rsync Upload'
LAST_UPDATED='2026-01-25'
SCRIPT_AUTHOR="Michael G Chu, https://github.com/michaelgchu/"

# -------------------------------
# "Constants", Globals / Defaults
# Most are actually stored in $ConfigFile, which is read at this time if available
# -------------------------------

# Force $USER variable, as it may not be available from cron
USER=$(whoami)

# Stores info about what to backup, to where, etc.
# If this file does not exist, then the user gets prompted to provide at least the ones we need to create local backups.
# - foldersToBackup : a colon-separated list of folders to back up
# - backupLocation  : where all backups get saved locally
# - baseName        : the start of the backup filenames
# - remoteServer : remote server to copy the backup file to after it is created
# - remoteUserID : your user ID on the remote server
# - remotePath   : path to save backup to on remote server
ConfigFile=/home/$USER/.config/create_backup.conf

# Read in the script config file right now, if it exists
# No need to check right here - that's done as normal processing further down
if [ -e "$ConfigFile" ] ; then
	eval $(cat "$ConfigFile") || { echo "ERROR: you have a config file but we cannot read it: $ConfigFile"; exit 1; }
fi

# How many incremental backups we should have before the script starts recommending a new full backup
limitIncremental=30

# --------------------------
# These are internal variables- no touchies
# --------------------------

backupFilenameTemplate='<BASENAME>-<YYYYMMDD>-L<LEVEL>.tar.gz'
snapshotFilenameTemplate='<BASENAME>-<YYYYMMDD>.snar'

lockfile="/var/lock/mgc_createbackup-$USER"

# Store each source folder into an element of an array
IFS=':' read -r -a srcPaths <<< "$foldersToBackup"

# Start preparing the filenames to use
fnBackup="${backupFilenameTemplate/<BASENAME>/$baseName}"
fnSnapshot="${snapshotFilenameTemplate/<BASENAME>/$baseName}"


# -------------------------------
# General Functions
# -------------------------------

Usage()
{
	fold --spaces << EOM
Usage: ${0##*/}  [options]

This script creates tar-based full or incremental backups of folders.  It is designed to be called daily or at logon; it has checks to prevent creating more than 1 backup per day. Once a backup set reaches $limitIncremental or more, it will display a message recommending you to create a new full backup.

The tarballs contain absolute paths, exclude any hidden files/folders, and are gzipped.
It does not exclude anything, i.e. hidden files will be included.

All details on what folders to backup, where to store them (including an optional remote server) are stored in a configuration file at:
	$ConfigFile
EOM
	test -z "$foldersToBackup" && echo -e "\n(You don't have this config file. Run without -h to create one)"
	test -n "$foldersToBackup" && fold --spaces << EOMlocal

-- Below is information taken from that configuration file --

The locations that get backed up:
$(	tr ':' '\n' <<< $foldersToBackup | cat -n )
Backup files are created at:
	${backupLocation}
Backup files follow the naming convention:
	$fnBackup
	(L00 indicates a full backup)
Each set has an associated snapshot file, which follow the naming convention:
	$fnSnapshot
EOMlocal
	test -n "$remoteServer" && fold --spaces << EOMremote
Remote server to upload backups to:
	$remoteServer
Remote user ID:
	$remoteUserID
Remote path to copy backups to:
	$remotePath
EOMremote

	fold --spaces << EOMopt

OPTIONS
   -h    Show this message
   -f    Create a Full backup
   -i    Create an Incremental backup
   -F    Force creation of backup even if one was already created today.
         For full backups, it renames the existing files to .bak first.
   -v    be Verbose

EOMopt
}


echoUL() {
# echo with Underline
	echo -e "\e[4m$*\e[24m"
}


QueryUser() {
# Prompt user for all required info
	local -a dirs # declare local indexed array to store directories
	local given canond
	fold --spaces << EOM
This script stores your settings into a config file at:
	$ConfigFile
This appears to be your first run, as we can't find that file.

If you want to learn more about this script, press CTRL-C to cancel and then run the script again like so:
	$0 -h

If you are ready to configure it, then please answer the following 3 questions, or 6 if you also want backup files to be uploaded to a remote server using rsync.
EOM

	echoUL '\n#1 Folders to Backup'
	echo 'This script can back up multiple locations. Please provide each path, one per line. Press ENTER on its own or CTRL-D to finish'
	while read -p 'Folder to backup: ' given; do
		test -z "$given" && break
		test -d "$given" || { echo 'Error: not a directory. Ignoring'; continue; } 
		test -r "$given" -a -x "$given" || { echo 'Error: cannot read. Ignoring'; continue; } 
		canond=$(readlink --canonicalize "$given")
		echo -e "\tAdding: $canond"
		dirs+=($canond)
	done
	test ${#dirs[@]} -gt 0 || return 1
	# Combine it all
	foldersToBackup=$(printf '%s:' "${dirs[@]}" | sed -r 's/:$//')

	echoUL '\n#2 Backups Directory Location'
	read -p 'Where on this machine should we store the backups: ' given
	test -d "$given" || { echo 'Error: not a directory'; return 1; }
	test -w "$given" -a -x "$given" || { echo 'Error: cannot write to that directory'; return 1; }
	backupLocation=$(readlink --canonicalize "$given")
	echo -e "\tBackup to: $backupLocation"

	echoUL '\n#3 Backup File Basename'
	echo "All backups are named like so: $backupFilenameTemplate"
	read -p 'What should the basename be: ' baseName
	test -z "$baseName" && { baseName='backup'; echo -e "\t(use default)"; }
	echo -e "\tBase name: $baseName"

	echoUL '\n#4 Remote Backup Server'
	echo 'Optionally, the script can upload the backup files to a remote server.'
	echo 'This is convenient if you have your public key installed to that server.'
	echo -e 'If you do not want to do this, then just press ENTER at the next prompt.\n'
	read -p 'IP address or DNS name of remote backup server: ' given
	test -z "$given" && { echo "No remote server will be used"; return 0; }
	echo -e '\tPing test of provided value ...'
	if ! ping -c 1 "$given" >/dev/null ; then
		# Ping failed!
		return 1
	fi
	remoteServer="$given"
	echo -e "\tRemote server: $given"

	echoUL '\n#5 Remote Server User ID'
	read -p 'What is your user ID on the remote server: ' given
	test -z "$given" && { echo "Sorry, you must provide a user ID"; return 1; }
	remoteUserID="$given"
	echo -e "\tRemote server user ID: $remoteUserID"

	echoUL '\n#6 Remote Backup Server Directory'
	echo 'This is the *absolute* path on the backup server to save the backup files to. The script will not test this - please ensure you provide it properly.'
	read -p 'Full absolute path on remote server to save backups: ' given
	test -z "$given" && { echo "Sorry, you must provide a path"; return 1; }
	test "${given:0:1}" = '/' || { echo 'Sorry, path must start from /'; return 1; }
	remotePath="$given"
	echo -e "\tRemote server backup path: $remotePath"

	return 0
}


WriteConfigFile() {
# Write configuration to file. Called after the user provides the values to write.
# It's written in such a way that we can just "eval" the contents
# This fcn Succeeds or aborts
	echo "Writing configuration to: $ConfigFile ..."
	cat <<- EOD > "$ConfigFile" || { echo 'Error writing config file!'; exit 1; }
		foldersToBackup=$foldersToBackup
		backupLocation=$backupLocation
		baseName=$baseName
	EOD
	if [ -n "$remoteServer" ] ; then
		# Remote stuff given. add that to config file too
		cat <<- EOD2 >> "$ConfigFile" || { echo 'Error writing config file!'; exit 1; }
			remoteServer=$remoteServer
			remoteUserID=$remoteUserID
			remotePath=$remotePath
		EOD2
	fi
}


# This function will be called on script exit, if required.
finish() {
	test $beVerbose = true && echo "Removing lockfile $lockfile ..."
	rm -f "$lockfile"
}


# ************************************************************
# Reading script args & basic tests
# ************************************************************

# printTitle()
echo -e "\e[4m$SCRIPTNAME ($LAST_UPDATED)\e[24m\n"

args="$*"

# Process script args/settings
createFull=false
createIncremental=false
beVerbose=false
forceBackup=false
while getopts ":hfiFv" OPTION
do
	case $OPTION in
		h) Usage; exit 0 ;;
		f) createFull=true ;;
		i) createIncremental=true ;;
		F) forceBackup=true ;;
		v) beVerbose=true ;;
		*) echo -e "\033[31mWarning: ignoring unrecognized option -$OPTARG \033[0m"
	esac
done
shift $(($OPTIND-1))

# Force user to answer all the questions now, if the config file is not present
if [ ! -e "$ConfigFile" ] ; then
	if ! QueryUser ; then
		echo 'Error or Insufficient info provided. Aborting'
		exit 1
	fi
	WriteConfigFile	# this will work, or die
	echo "Success. Please run this script again. It'll work normally now"
	exit 0
fi

# Ensure we're good to go
test $createFull = true -a $createIncremental = true && { echo 'Error: you cannot specify both full AND incremental'; exit 1; }
test $createFull = true -o $createIncremental = true || { echo 'Choose full OR incremental backup. Run with -h for help.'; exit 1; }
if $createFull ; then
	backupType='full'
else
	backupType='incremental'
fi

# For notifying user if we've hit the threshold for # of incremental backups
for cmd in zenity xmessage
do
	hash $cmd &>/dev/null && { beep_cmd=$cmd ; break; }
done



# ************************************************************
# Main Line
# Perform a few checks before we do any work
# ************************************************************

today=$(date +%Y%m%d)

# Check the paths - combine all possible data paths & backup location
for p in "$backupLocation" "${srcPaths[@]}"; do
test $beVerbose = true && echo "Checking folder: $p"
	test -e "$p" -a -d "$p" -a -x "$p" || { echo "Error: folder '$p' does not exist or has bad permissions"; exit 1; }
done
test -w "$backupLocation" || { echo "Error: folder '$backupLocation' has no write permissions"; exit 1; }

# Additional checks / steps before taking action
# This involves finishing setting up the filenames required
if [ $backupType = 'full' ] ; then
	# Full Condition: Only do it once per day. The filename contains the run date, so it's a simple check
	fnBackup="${fnBackup/<YYYYMMDD>/$today}"
	fnBackup="${fnBackup/<LEVEL>/00}"
	fnSnapshot="${fnSnapshot/<YYYYMMDD>/$today}"
	fpBackup="$backupLocation/$fnBackup"
	fpSnapshot="$backupLocation/$fnSnapshot"
	if [ -e "$fpBackup" -a -e "$fpSnapshot" ] ; then
		echo "Backup '$fnBackup' already created today."
		test $forceBackup = false && { echo 'You can force a redo using -F'; exit 0; }
		echo 'Moving/renaming existing files ...'
		mv -v "$fpBackup" "$fpBackup.bak"
		mv -v "$fpSnapshot" "$fpSnapshot.bak"
	fi
else # Incremental
	# Conditions for incremental:
	# - a full backup already exists, plus a related snapshot
	# - no incremental was created today
	# First step: identify the latest full backup in the backup folder
	# Assemble the file pattern manually
	fpFull=$(ls -1 "$backupLocation/${baseName}-"*'-L00.tar.gz' 2>/dev/null | tail -1)
	test -z "$fpFull" && { echo 'Error: no full backup exists. Create one of those first'; exit 1; }
	fnFull=$(basename "$fpFull")
	ymd=$(grep -oP '\d{8}' <<< $fnFull)
	test $beVerbose = true && echo "Latest full backup identified: $fnFull"
	# From the full backup filename, generate the snapshot. Confirm it exists
	fnSnapshot="${fnFull/-L00.tar.gz/.snar}"
	fpSnapshot="$backupLocation/$fnSnapshot"
	test -e "$fpSnapshot" || { echo "Error: full backup found, but not the associated snapshot!"; exit 1; }
	# Determine the latest (incremental) backup for this set
	fpLatest=$(ls -1 "$backupLocation/${baseName}-${ymd}-L"*'.tar.gz' 2>/dev/null | tail -1)
	# Check when this latest file was created
	latestYMD=$(date --reference="$fpLatest" +%Y%m%d)
	if [ $latestYMD = $today ] ; then
		echo "Backup '$fpLatest' already created today."
		test $forceBackup = false && exit 0
	fi
	# Increment the filename, ex. L01 > L02
	# Extract number, then remove leading zeros, as it may create problems at special numbers like 08
	currLevel=$(grep -oP '(?<=L)\d\d(?=\.tar.gz)' <<< "$fpLatest" | sed -r -e 's/^0+//')
	nextLevel=$((currLevel + 1))
	fnBackup=$(printf "${baseName}-${ymd}-L%02d.tar.gz" $nextLevel)
	fpBackup="$backupLocation/$fnBackup"
fi


# Getting to this point means we are good to do the backup
# The filepath variables are already set above.
test -e "$lockfile" && { echo "Error: lockfile $lockfile already exists -- please check on prior execution of this script"; exit 2; }
# It's a trap! ... to help with cleanup
trap finish EXIT
touch "$lockfile"
test $beVerbose = true && echo 'Lockfile created, ready to perform backup'


# The backup command is effectively the same, regardless of full vs incremental!
echo 'Creating backup ...'
tar --verbose --create \
	--file="$fpBackup" \
	--listed-incremental="$fpSnapshot" \
	--absolute-names \
	"${srcPaths[@]}"
#	--exclude='.*' \

if [ $? -ne 0 ] ; then
	echo "Error occurred! Deleting created backup file:"
	rm -v "$fpBackup"
	exit 1
fi

# Success. Display some outputs
cat << EOM

Backup type    : $backupType
Backup created : $fpBackup
Snapshot file  : $fpSnapshot

EOM


# Check if we should be uploading the backup files now
if [ -n "$remoteServer" ] ; then
	echo 'Begin upload of backup & snapshot files to remote server --'
	echo "Connecting as $remoteUserID to $remoteServer, uploading to $remotePath ..."
	rsync -avzh "$fpBackup"   "$remoteUserID@$remoteServer:$remotePath" || { echo 'Error uploading!'; exit 1; }
	rsync -avzh "$fpSnapshot" "$remoteUserID@$remoteServer:$remotePath" || { echo 'Error uploading!'; exit 1; }
	echo -e '\nUploads successful!\n'
elif [ $backupType = 'full' ] ; then
	echo "Recommended next step: copy this full backup off the system"
fi

# Finally, check if we should recommend to start over with a full vs incremental
if [ $backupType = 'incremental' ] ; then
	if [ -a $nextLevel -ge $limitIncremental ] ; then
		message="Recommended next step: this set has many incremental backups now. Consider starting a new full backup"
		echo $message
		case $beep_cmd in
			zenity)   zenity --info --text="$message" ;;
			xmessage) xmessage -center "$message" 2>/dev/null ;;
		esac
	fi
fi
#EOF
