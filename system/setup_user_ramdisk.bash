#!/usr/bin/env bash
SCRIPTNAME='Setup User RAMdisk'
LAST_UPDATED='2025-01-17'
SCRIPT_AUTHOR="Michael G Chu, https://github.com/michaelgchu/"

# -------------------------------
# "Constants", Globals / Defaults
# -------------------------------

# foldersToSymlink : a colon-separated list of your $HOME directory folders to convert to symlinks pointing to RAMdisk locations. Add more as you please.
# The whole Brave Browser folder is fresh every time with this setup - remove that entry if you don't want that
foldersToSymlink='.cache:.config/chromium/Default/Service Worker/CacheStorage:.config/libreoffice/4/cache:.config/BraveSoftware/Brave-Browser'

# Store each source folder into an element of an array
IFS=':' read -r -a srcPaths <<< "$foldersToSymlink"


# -------------------------------
# General Functions
# -------------------------------

Usage()
{
	fold --spaces << EOM
Purpose
=======
This script will help people that have a RAM disk set up for temporary disk usage, whether the goal is for reduced wear & tear, faster read/write operations, etc.

Usage
=====
Place an entry to this script within your crontab entry, like so:
	@reboot $(readlink --canonicalize "$0")
Every time your computer (re)boots, personal folders will be created on the RAM disk, and then symbolic links to those folders will be created for:
$( for p in "${srcPaths[@]}"; do echo -e "*\t~/$p"; done )
Additionally, a symlink 'ramdisk' gets created in your ~/Downloads/ folder.


Requirements
============
For this script to work, your  /etc/fstab  must have a single 'tmpfs' entry
that establishes your RAM disk.
Ex. this line establishes a 4GB RAM disk at mount point /ramdisk:
	myramdisk /ramdisk tmpfs defaults,noatime,nodev,mode=1777,size=4096M 0 0
EOM
}

printTitle()
{
	title="$SCRIPTNAME ($LAST_UPDATED)"
	echo "$title"
	printf "%0.s-" $(seq 1 ${#title})
	echo 
}


# ************************************************************
# Main Line
# ************************************************************

printTitle

if [ "$*" = '-h' -o "$*" = '--help' ] ; then
	Usage
	exit 0
fi

# Force $USER variable, as it may not be available from cron
USER=$(whoami)

# Confirm there is exactly 1 RAMdisk entry in /etc/fstab
if [ $(grep --count -P '^[^#]+\stmpfs\s' /etc/fstab) -ne 1 ] ; then
	echo 'Your /etc/fstab does not have exactly 1 "tmpfs" entry. This script is not configured to handle that.'
	exit 1
fi
# Get the mount point of the single defined RAMdisk
folderRD=$(awk '{ if ( $3 == "tmpfs" ) print $2 }' /etc/fstab)
test -n "$folderRD" || { echo 'Error getting RAMdisk from /etc/fstab'; exit 1; }

echo "Found defined RAMdisk in /etc/fstab as: $folderRD"

# Wait for the RAMdisk to get mounted
echo "Waiting until the RAMdisk is mounted ..."
while ! grep "${folderRD} tmpfs" /etc/mtab >/dev/null
do
	sleep 1
done

# Setting up folders in RAMdisk
echo "Creating folders as needed in the RAMdisk at ${folderRD}/${USER} ..."
mkdir --verbose --parents "${folderRD}/${USER}"
chmod --verbose 700       "${folderRD}/${USER}"
#mkdir --verbose --parents "${folderRD}/${USER}/"{.cache,.config/BraveSoftware/Brave-Browser,Downloads}
for p in "${srcPaths[@]}"; do
	mkdir --verbose --parents "${folderRD}/${USER}/${p}"
done
mkdir --verbose --parents "${folderRD}/${USER}/Downloads"

# Now make symlinks to these RAMdisk locations. Back up any existing stuff
echo "Establishing symlinks to RAMdisk ..."
for p in "${srcPaths[@]}"; do
	if [ -L ~/"$p" ] ; then
		echo "~/$p already exists as a symlink."
	else
		if [ -e ~/"$p" ] ; then
			echo "~/$p exists and is not a symlink ..."
			if [ -e ~/"$p.bak" ] ; then
				echo "A ~/$p.bak entry already exists. Aborting."
				exit 1
			fi
			mv -vi ~/"$p" ~/"$p.bak"
		fi
		ln --verbose --symbolic "$folderRD/$USER/$p" ~/"$p"
	fi
done

# This one is different: ADD a symlink instead of REPLACING the original folder
if [ -L ~/Downloads/ramdisk ] ; then
	echo "~/Downloads/ramdisk already exists as a symlink."
else
	if [ -e ~/Downloads/ramdisk ] ; then
		echo "~/Downloads/ramdisk exists and is not a symlink. Aborting."
		exit 1
	fi
	ln --verbose --symbolic "${folderRD}/${USER}/Downloads" ~/Downloads/ramdisk
fi

echo 'Setup complete.'
