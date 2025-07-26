#!/usr/bin/env bash
SCRIPTNAME='Search within Markdown Vault'
LAST_UPDATED='2025-07-25'
# Author: Michael Chu, https://github.com/michaelgchu/
# See Usage() for purpose and call details
#
# Updates
# =======
# 2025-07-25
# - improved regex pattern for requiring all keywords, reducing search time (made them "lazy")
# - other improvements/fixes
# 2025-07-21
# - Bug fixes for use in WSL, so it can open in VSCode
# 2025-07-19
# - First version, based on https://github.com/michaelgchu/Shell_Scripts_Cygwin/blob/master/documentation/mdsearch.bash

# -------------------------------
# "Constants", Globals
# -------------------------------

# SearchPath: The directory structure to search for Markdown files
# You can put symbolic links in here to be able to search multiple locations.
# The script tries grabbing the environment variable VAULT_FOLDER first.
# Failing that, it will try $XDG_DOCUMENTS_DIR and finally good ol' $HOME
SearchPath=${VAULT_FOLDER:-$XDG_DOCUMENTS_DIR}
: ${SearchPath:=$HOME}


# -------------------------------
# Functions
# -------------------------------

Usage()
{
	printTitle
	cat << EOM
Usage: ${0##*/} [options] [keyword(s) | regex]

Search your collection of Markdown files for the specified keywords and either list (default) or display / open them.

By default, it looks for filepaths matching the provided keywords. Alternatively, you can search for text matches within the files. Or do both!

The following directory is searched for files:
	$SearchPath
The script selected this directory based on looking for the following environment variables:
	\$VAULT_FOLDER > \$XDG_DOCUMENTS_DIR > \$HOME
You can specify a different directory to search.

Any symbolic links will be followed as it looks for text files that have a  .md  or  .markdown  extension.

When opening matching files,
- explorer.exe  will be used if available (WSL)
- less          will be used otherwise
- mdv           will be used if available and requested
(Unfortunately, not sure how to get files to open in Obsidian on Linux.)

OPTIONS
=======
-h    Show this message
-q    Quiet mode: only print the final output
-p <directory to search within>
Search options:
-C    Case sensitive search (default is insensitive)
-c    Content-based search, instead of the default filepath-based
-f    With -c, the script will also do a filepath-based search
-a    All keywords must be present for a file to be considered a match
-L    All keywords must be present on the same line (implies  -a )
-r    Treat provided argument as a Perl regular expression
Resulting Action:
-l    List the matching files; do not display/open (default)
-o    Open / print the matching files
List Options
------------
-g    Use grep to display the matching lines within the files
      (May not work well with the  -r  regex option)
For listing results with grep:
   -t #  Show a max of # hits per file
   -n    Show line Numbers for the matches
   -x #  Include # lines of conteXt
Open / Print Options
--------------------
-m    Use mdv (Terminal Markdown Viewer) to display
For printing with mdv:
   -N    Do not pause between viewing Markdown files
   -P    Do not use a pager ('less')

EOM
}

printTitle() {
	title="$SCRIPTNAME ($LAST_UPDATED)"
	echo "$title"
	printf "%0.s-" $(seq 1 ${#title})
	echo 
}


# -------------------------------
# Main Line
# -------------------------------

# Process script args/settings
path="$SearchPath"
FinalAction='list'
FilepathSearch=false
NeedAllKeywords=false
NeedOnSameLine=false
ContentSearch=false
CaseSensitive=false
PauseInBetween=true
UsePager=true
IsRegex=false
GrepToDisplay=false
grepOpt=(--text --with-filename --perl-regexp --color=yes)
UseMdv=false
BeQuiet=false
while getopts ":hqp:CcfaLrlgoPmt:nx:N" OPTION
do
	case $OPTION in
		h) Usage; exit 0 ;;
		q) BeQuiet=true ;;
		p) path="$OPTARG" ;;
		C) CaseSensitive=true ;;
		c) ContentSearch=true ;;
		f) FilepathSearch=true ;;
		a) NeedAllKeywords=true ;;
		L) NeedAllKeywords=true; NeedOnSameLine=true ;;
		r) IsRegex=true ;;
		l) FinalAction='list' ;;
		o) FinalAction='open' ;;
		P) UsePager=false ;;
	# List Options
		g) FinalAction='list'; GrepToDisplay=true ;;
		t) grepOpt+=(--max-count=$OPTARG) ;;
		n) grepOpt+=(--line-number) ;;
		x) grepOpt+=(--context=$OPTARG) ;;
	# Open/print Options
		m) FinalAction='open'; UseMdv=true ;;
		N) PauseInBetween=false ;;
		*) echo "Warning: ignoring unrecognized option -$OPTARG" ;;
	esac
done
shift $(($OPTIND-1))

# Any leftover arguments are used as keywords - or a single regex
if [ $# -eq 0 ]; then
	echo 'You must supply at least 1 keyword to search for. Run with -h for help'
	exit 1
fi
# If using regex, there should be just 1 argument
if $IsRegex ; then
	if [ $# -ne 1 ] ; then
		echo 'Enclose your regex pattern in quotes, please. Run with -h for help'
		exit 1
	fi
	# Some options don't make sense in this mode, so set to false for run display purposes
	NeedAllKeywords=false; NeedOnSameLine=false
fi

# Enable filepath search, if Content search wasn't explicitly requested
test $ContentSearch = false && FilepathSearch=true

# Add a trailing slash to the path, if not already there
path=$(tr -s '/' <<< "${path}/")
# Ensure directory is good
test -n "$path" -a -d "$path" -a -r "$path" || { echo "ERROR: '$path' is not a readable dir"; exit 1; }

# If we'll be opening files, ensure we have a tool for that
if [ $FinalAction = 'open' ] ; then
	if $UseMdv ; then
		# Test for mdv
		hash mdv &>/dev/null || { echo "Error: command 'mdv' not present. Refer to: https://github.com/axiros/terminal_markdown_viewer"; exit 1; }
		OpenWith='mdv'
	else
		if hash explorer.exe &>/dev/null ; then
			OpenWith='explorer.exe'
		elif hash less &>/dev/null ; then
			OpenWith='less'
		else
			echo "Sorry, I don't know how to open files on your system. Could not find less or explorer.exe"
			exit 1
		fi
	fi
fi

# Set all the flags/switches for our tools based on script call

if $CaseSensitive ; then
	caseFlag=''
else
	caseFlag='i' ; grepOpt+=(--ignore-case)
fi

if $UsePager ; then
	mdvFUcmd=(less -R)
else
	mdvFUcmd=(cat)
fi


# -------------------------------
# Prepare the Perl regex pattern that will be used for ALL searching - whether the user wants a filepath search, content search, or both
# -------------------------------
if $IsRegex ; then
	# this is easy. They gave us the exact pattern to apply!
	pattern="$1"
else
	if $NeedAllKeywords ; then
		# When all keywords must exist, we use positive lookaheads for each keyword.
		# e.g. given the keywords 'proxy' & 'blender', the pattern will be:
		#	(?=[\d\D]*?proxy)(?=[\d\D]*?blender)
		# Supposedly, anchoring with '^' improves peformance. We add that on execution.
		# Explanation of the  perl  command:
		# 1. Trim whitespace from front and back, if any
		# 2. Escape any regex metacharacter
		# 3. Capture each keyword and wrap it with positive lookahead syntax
		if $NeedOnSameLine ; then wildcard='.'; else wildcard='[\\d\\D]'; fi
		pattern="$( perl -p -e '
			s/^ +| +$//g;
			s/([\\^$|()\[\].+*?{}])/\\$1/g;
			s/([\S]+)(\s+|$)/(?='"$wildcard"'*?$1)/g;' <<< "$@" )"
	else
		# When we can take any keyword, the regex is much simpler:  alternation.
		# e.g. given the keywords 'proxy' & 'blender', the pattern will be:
		#	(proxy|blender)
		# Explanation of the  perl  command:
		# 1. Trim whitespace from front and back, if any
		# 2. Escape any regex metacharacter
		# 3. Replace every set of spaces with a single pipe
		# 4. Enclose everything in parentheses
		pattern="$( perl -p -e '
			s/^ +| +$//g;
			s/([\\^$|()\[\].+*?{}])/\\$1/g;
			s/ +/|/g;
			s/^/(/; s/$/)/' <<< "$@" )"
	fi
fi


# -------------------------------
# Summary of call to stderr
# -------------------------------

test $BeQuiet = 'false' && cat > /dev/stderr <<- EOM
	Path                 : $path
	Case sensitive       : $CaseSensitive
	Content search       : $ContentSearch
	Filepath search      : $FilepathSearch
	Require all keywords : $NeedAllKeywords
	... on same line     : $NeedOnSameLine
	Provided Perl regex  : $IsRegex
	Resulting Action     : $FinalAction
	Keywords/regex : $@
	[Built regex   : $pattern ]

EOM


# -------------------------------
# Search for the files
# First we get ALL files in the directory, then
# a) Potentially filter by keywords/regex against the filepaths
# b) Potentially filter by keywords/regex against the content of the files
# -------------------------------

# Produce a list of Markdown files within the directory, then potentially
# filter on the filepath. In either case, we use process substitution to send
# results to Bash's 'readarray', which will place it all into a single array.
if $FilepathSearch ; then
	# Within the process substitution, we are:
	# 1. Generating a list of all Markdown files within the data folder
	# 2. Feed these to a Perl command, which will filter on the keywords/regex 
	#    and also insert the full path to all matches, for later processing
	readarray -d $'\0' hits <   <(
		find "$path" -follow -regextype 'posix-extended' -type f -iregex ".*\.(markdown|md)$" -printf '%P\0' |
		perl -0 -n -e "\$ins = '$path'; if (/${pattern}/${caseFlag}) { s/^/\$ins/; print }"
	)
else
	# No filtering required, just find all the Markdown files
	readarray -d $'\0' hits <   <(
		find "$path" -follow -regextype 'posix-extended' -type f -iregex ".*\.(markdown|md)$" -print0
	)
fi

# Whether we do content search or not, the final filtered list gets stored in array 'theFiles'
if $ContentSearch ; then
	test $BeQuiet = 'false' && echo "Initial find & filepath filtering identifies ${#hits[@]} files ..." > /dev/stderr
	# Within the process substitution, we:
	# 1. Dump the list of files, nul-separated, to xargs, so all get passed to Perl as command-line args
	# 2. Build up a Perl script that will open every file to filter for matches.
	#    (The '$/' is to read all contents into a single var.)
	readarray -d $'\0' theFiles < <(
		printf "%s\0" "${hits[@]}"  | xargs -0 perl <( cat <<- EndPerl
			foreach my \$filename (@ARGV)
			{
				open(FILE, "\$filename");
				local \$/ = undef;
				\$lines = <FILE>;
				close(FILE);
				print "\$filename\0" if (\$lines =~ /${pattern}/${caseFlag});
			}
			EndPerl
		)
	)
else
	# Perform straight copy of one array into another
	theFiles=("${hits[@]}")
fi

test $BeQuiet = 'false' && echo "Found ${#theFiles[@]} files" > /dev/stderr

# If no files were found, then we stop here
test ${#theFiles[@]} -eq 0 && exit 0


# -------------------------------
# Handle the files found
# -------------------------------
test $BeQuiet = 'false' && echo ------------------------- > /dev/stderr

if [ $FinalAction = 'list' ] ; then
	if $GrepToDisplay ; then
		# Run everything through grep, then trim filepaths
		printf "%s\0" "${theFiles[@]}" |
		xargs -0 grep --regexp="$pattern" ${grepOpt[@]} |
		sed -r -e "s<^([^/]*)$path<\1<" # | ${mdvFUcmd[@]}
	else
		# Normal listing
		# Print each filepath on a line, then cut off the base path
		printf "%s\n" "${theFiles[@]}" | cut --characters=$((${#path} + 1))-
	fi
else # action = 'open'
	if [ $OpenWith = 'less' ] ; then
		printf "%s\0" "${theFiles[@]}"  | xargs -0 less
	else
		for (( i=0; i < ${#theFiles[@]}; i++ ))
		do
			test $BeQuiet = 'false' && echo "Opening match $((i+1)): ${theFiles[i]}" > /dev/stderr
			if [ $OpenWith = 'mdv' ] ; then
				$OpenWith "${theFiles[i]}" | ${mdvFUcmd[@]}
				if [ $PauseInBetween = true -a $i -gt 0 ] ; then
					echo "Next file: ${theFiles[i]}" > /dev/stderr
					echo "Press ENTER to continue or CTRL-C to cancel" > /dev/stderr
					read
				fi
			else
				# For explorer.exe, seems we have to be in the folder for it to open
				cd "$(dirname "${theFiles[i]}")"
				$OpenWith "$(basename "${theFiles[i]}")"
			fi
		done
	fi
fi

#EOF
