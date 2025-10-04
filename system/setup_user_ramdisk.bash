#!/usr/bin/env bash
SCRIPTNAME='Setup User RAMdisk'
LAST_UPDATED='2024-11-11'
SCRIPT_AUTHOR="Michael G Chu, https://github.com/michaelgchu/"

if [ "$*" = '-h' -o "$*" = '--help' ] ; then
	echo -e "\033[1;4mPurpose\033[0m
This script will help people that have a RAM disk set up for temporary disk
usage, whether the goal is for reduced wear & tear, faster read/write
operations, etc.

\033[1;4mUsage\033[0m
Place an entry to this script within your crontab entry, like so:
	@reboot $(readlink --canonicalize "$0")
Every time your computer (re)boots, personal folders will be created on the RAM
disk, and then symbolic links to those folders will be created for:
* ~/.cache
* ~/Downloads/ramdisk

\033[1;4mRequirements\033[0m
For this script to work, your  /etc/fstab  must have a single 'tmpfs' entry
that establishes your RAM disk.
Ex. this line establishes a 4GB RAM disk at mount point /ramdisk:
	myramdisk /ramdisk tmpfs defaults,noatime,nodev,mode=1777,size=4096M 0 0
"
	exit 0
fi

# Force $USER variable, as it may not be available from cron
USER=$(whoami)

# Confirm there is exactly 1 RAMdisk entry in /etc/fstab
if [ $(grep --count tmpfs /etc/fstab) -ne 1 ] ; then
	echo 'Your /etc/fstab does not have exactly 1 "tmpfs" entry. This script is not configured to handle that.'
	exit 1
fi
# Get the mount point of the single defined RAMdisk
folderRD=$(awk '/ tmpfs / { print $2 }' /etc/fstab)
echo "Found defined RAMdisk in /etc/fstab as: $folderRD"

# Wait for the RAMdisk to get mounted
echo "Waiting until the RAMdisk is mounted ..."
while ! grep "${folderRD} tmpfs" /etc/mtab >/dev/null
do
	sleep 1
done

# Setting up folders in RAMdisk
echo "Creating your user folders in the RAMdisk at ${folderRD}/${USER} ..."
mkdir --verbose --parents "${folderRD}/${USER}"
chmod --verbose 700       "${folderRD}/${USER}"
mkdir --verbose --parents "${folderRD}/${USER}/"{.cache,Downloads}

# Now make symlinks to these RAMdisk locations. Back up any existing stuff
echo "Establishing symlinks to RAMdisk ..."

if [ -L ~/.cache ] ; then
	echo "~/.cache already exists as a symlink."
else
	if [ -e ~/.cache ] ; then
		echo "~/.cache exists and is not a symlink ..."
		if [ -e ~/.cache.bak ] ; then
			echo "A ~/.cache.bak entry already exists. Aborting."
			exit 1
		fi
		mv -vi ~/.cache ~/.cache.bak
	fi
	ln --verbose --symbolic "${folderRD}/${USER}/.cache" ~/.cache
fi
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
