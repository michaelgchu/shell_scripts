#!/usr/bin/env bash
# A reset of mps-youtube, based off info provided by MJ-X on youtube
# Call this when mpsyt doesn't work
# e.g. It aborts immediately with error messages that end with:
# pafy.util.GdataError: Youtube Error 403: The request cannot be completed because you have exceeded your <a href="/youtube/v3/getting-started#quota">quota</a>.

# Wiping the cache should take care of Youtube Error 403
echo Deleting mps-youtbe cache ...
rm ~/.config/mps-youtube/cache_py*

echo Testing if everything is OK now by running a test search ...
mpsyt "/weird al, q"
if [ $? -ne 0 ] ; then
	echo Search failed. Updating youtube-dl ...
	pip3 install youtube-dl -U
fi

echo Starting mps-youtube ...
mpsyt

#EOF
