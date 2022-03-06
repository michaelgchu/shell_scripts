#!/usr/bin/env perl
my $SCRIPTNAME   = 'Record/Regex Filter';
my $LAST_UPDATED = '2022-03-06';
# Author: Michael Chu, https://github.com/michaelgchu/
# See Usage() for purpose and call details
# Credits: the pattern to identify a field and its preceding delimiter is taken
# from Jeffrey E.F. Friedl's "Mastering Regular Expressions" (3rd ed, pg 271)
# TODO:
# - bug fix: identify & discard bad content, e.g. unescaped "s
# - add ability to specify column Name
# - add colour to the debug/verbose output
use strict;
use Getopt::Std;

sub usage() {
	print << "EOD";
$SCRIPTNAME ($LAST_UPDATED)
Usage: $0 <options> pattern [file]

Filters delimited data by applying the provided regular expression 'pattern'.
It is like grep, except:
- it will always print the header (line 1)
- it works on "records" that can extend onto multiple lines of text, so you
  can filter CSV's with fields containing embedded line breaks
- it will only process a single source: either STDIN, or a named file
- the pattern must always be provided as PRCE (since this is a Perl program)

Records must meet these rules, otherwise they will be discarded:
- have the exact same number of fields as the header
- each field must either
  - contain no delimiter or double-quote characters
  - start & end with double-quotes, and any double-quotes within these
    enclosing characters are escaped by repeating them
(Some bad content may prevent the tool from working properly.)

As an example, consider the following text file and program call:

   \$ cat -n good2_bad2.csv
        1  Col1,Col2,Col3
        2  first,second,third
        3  A,"The ""cake"", is, a, lie",C
        4  too,many,fields,in,this,line
        5  This,"record has
        6  a line break hehe","and that's ok!"
        7  too,"few fields"
   \$ $0 -c 2 'e\$' good2_bad2.csv
   Col1,Col2,Col3
   A,"The ""cake"", is, a, lie",C
   This,"record has
   a line break hehe","and that's ok!"

OPTIONS
-------
    -c column#       The column # to filter on. Mandatory, unless -w is used
    -d delimiter     Default: comma  ,
    -h               This help screen
    -i               Apply case insensitivity regex switch via (?i)
    -m               Apply multiline regex switch          via (?m)
    -s               Apply dot-matches-all regex switch    via (?s)
    -v               Print verbose messages on STDERR
    -w               Apply pattern to Whole record
    -D               Print debug messages on STDERR

EOD
	exit 0;
}

# ==============================================================
# Program defaults, globals
# ==============================================================
my $delimiter = ',';
# There's probably a better way to handle all these settings and stuff
# Perhaps by returning & passing hashes? https://beginnersbook.com/2017/02/subroutines-and-functions-in-perl/
my ($key_column, $num_fields, $key_pattern,
    $whole_record, $be_verbose, $be_debuggin, $mode_modifiers,
    $content_pattern,
    $ro_counting, $ro_test_record, $ro_selector, $ro_filter,
    $tally_bad, $tally_filtered, $tally_excluded
    );

# ==============================================================
# Main Line
# ==============================================================
handle_commandline_args();	# sets global variables
build_regex_objects_1(); 	# build patterns required for the header
process_line1();		# read/analyze line 1
build_regex_objects_2();	# build all remaining regex objects
process_body();			# read/filter remaining input
print_report();			# display tallies with -v

# ==============================================================
# Subroutines
# ==============================================================

sub handle_commandline_args() {
	# Process all the switches
	my %opts;
	getopts('c:d:himsvwD', \%opts) or usage();
	usage() if $opts{h};
	$be_verbose   = $opts{v};
	$be_debuggin  = $opts{D};
	$whole_record = $opts{w};
	$key_column   = $opts{c} if($opts{c}); # ignored if -w used
	if ($opts{d}) {
		# Grab the delimiter and escape any regex metachar
		$delimiter = $opts{d};
		my $count = $delimiter =~ s/([\\^$|()\[\].+*?{}])/\\$1/g;
		debugprint("Escaped $count regex metacharacter(s) in provided delimiter") if $count;
	}
	$mode_modifiers = '';
	$mode_modifiers .= '(?i)' if $opts{i};
	$mode_modifiers .= '(?m)' if $opts{m};
	$mode_modifiers .= '(?s)' if $opts{s};
	# Process all the remaining arguments - there must be at least 1
	$key_pattern = shift @ARGV if $ARGV[0];
	# Abort if some key values were not provided
	die "Provide your filtering pattern as the first non-switch argument. Run with -h for help\n" unless defined($key_pattern);
	if ($whole_record) {
		$key_column = -1;
		debugprint('Will filter on entire record');
	}
	else {
		die "Supply a column # to filter on using -c. Run with -h for help\n" unless defined($key_column);
		die "Column number must be positive\n" if ($key_column < 1);
		debugprint("Will filter on column $key_column");
	}
	# Do not allow multiple files to be provided
	die "Error: supply at most 1 filename to process\n" if ($#ARGV >= 1);
	if ($#ARGV == 0) {
		# Test the single file provided
		my $fn = $ARGV[0];
		die "'$fn' does not exist\n" if (! -e $fn);
		die "'$fn' is not readable\n" if (! -r $fn);
		die "'$fn' is not a text file\n" if (! -T $fn);
	}
}


# Do what we can/must without having seen the header
sub build_regex_objects_1() {
	# This pattern is for the individual field content, with no capture groups
	# It's used to test the header, so we must define it before reading in line 1.
	# It's also used for most of the other patterns!
	$content_pattern    = '(?:"(?>[^"]*)(?>""[^"]*)*"|[^"' . $delimiter . ']*)';

	# This is the data filtering pattern, which will have mode modifiers
	# inserted at the front if any of the i/m/s arguments were provided
	my $filter_pattern  = $mode_modifiers . $key_pattern;
	$ro_filter   = qr/$filter_pattern/o;
	debugprint("Pattern for filtering: $ro_filter ");

	# This pattern will find a complete field from a delimited record, including its preceding delimiter.
	# It contains no capture groups, so the count we get is the # of times the entire pattern matches.
	# The addition of the  \G metachar ensures no skips between successive matching elements.
	my $counting_pattern = '\G(?:^|' . $delimiter . ')(?:"(?>[^"]*)(?>""[^"]*)*"|[^"' . $delimiter . ']*)';
	$ro_counting   = qr/$counting_pattern/o;
	debugprint("Regex object for counting: $ro_counting ");
}


# Read/print line 1, and analyze it to determine how many fields each record should contain.
sub process_line1 {
	my $line1 = <>;
	$num_fields = count_fields($line1);
	debugprint("Delimiter= '$delimiter'");
	verboseprint("# fields = $num_fields");
	print $line1;
	# Check that the header string is valid, meaning each field/label either
	# a) starts & ends with d-quotes, possibly containing delimiters or doubled d-quotes within
	# b) contains no d-quotes or commas
	my $full_line_pattern = "^$content_pattern(?:$delimiter$content_pattern" . ')*$';
	die "Bad header line - aborting" unless $line1 =~ m/$full_line_pattern/;
	# Finally, quick check on requested column # filtering
	die "Column number exceeds field count - aborting" if ($key_column > $num_fields);
}


# Once all script parameters are received and header inspected, we can compile
# all our patterns into regex objects
sub build_regex_objects_2() {
	# This pattern checks that the provided string is a complete record,
	# as in it has exactly the same field count as the file header
	my $other_count = $num_fields - 1; # Subtract 1 for the 1st field
	my $fixed_num_fields = "^$content_pattern";
	$fixed_num_fields .= "(?:$delimiter$content_pattern){$other_count}" if ($other_count > 0);
	$fixed_num_fields .= '$';
	$ro_test_record    = qr/$fixed_num_fields/o;

	# This pattern is used to pull out the key field (to filter on)
	# However, it will take the enclosing double-quotes, so that will have
	# to be removed before applying the filter
	my $field_capture_pattern;
	$field_capture_pattern = "^($content_pattern)";
	if ($key_column > 1) {
		$other_count = $key_column - 1; # Subtract 1 for the 1st field
		$field_capture_pattern .= "(?:$delimiter($content_pattern)){$other_count}";
	}
	$ro_selector   = qr/$field_capture_pattern/o;
	debugprint("Regex object for column selection: $ro_selector ");
}


# The main loop that reads in the rest of the data, builds up records as
# necessary, then applies the filtering.
sub process_body() {
	my $record = '';	# for building up a multi-line record
	my $mlr_start = 2;	# for displaying start/end points of multi-line records
	$tally_bad = 0; $tally_filtered = 0; $tally_excluded = 0;
	while (my $line = <>) {
		if (is_record_ok($line)) {
			if ($record) {
				verboseprint("Dropping bad record from lines $mlr_start - ", $. - 1);
				$record = ''; # reset for the next loop iteration
				$tally_bad++;
			}
			apply_filter($line);
			$mlr_start = $. + 1;
			next;
		}
		# Keep/begin compiling a record from this line, which alone doesn't amount to a full record
		$record .= $line;
		if (is_record_ok($record)) {
			apply_filter($record);
			$record = ''; # reset for the next loop iteration
			$mlr_start = $. + 1;
			next;
		}
		my $count = count_fields($record);
		if ($count > $num_fields) {
			verboseprint("Dropping bad record from lines $mlr_start - $.");
			$record = '';
			$mlr_start = $. + 1;
			$tally_bad++;
		}
		elsif ($be_debuggin) {
			debugprint("Compiling at line $., field count = $count");
		}
	} # end while loop
	if ($record) {
		# Hit EOF while building up a record, so scrap it
		verboseprint("Dropping bad record from lines $mlr_start - end");
		$record = '';
		$tally_bad++;
	}
}


# Check if the provided string is a complete record, as in it has exactly the
# same field count as the file header
sub is_record_ok {
	return ($_[0] =~ m/$ro_test_record/);
}


# Get the count of fields from the provided string
sub count_fields {
	my @matches = $_[0] =~ m/$ro_counting/g;
	return scalar @matches;
}


# Grab the requested field from the line/record (or all of it), then test using
# the provided pattern.
sub apply_filter () {
	my $text;
	if ($whole_record) {
		$text = $_[0];	# take the whole thing
	}
	else {
		debugprint("Record       : -=$_[0]=- ");
		$_[0] =~ m/$ro_selector/ ; # apply regex to capture correct field
		$text = $+;	# take the last match == key column
		$text =~ s/^"//; $text =~ s/"$//; # remove any enclosing double-quotes
		debugprint("Captured text: -=$text=- ");
	}
	if ($text =~ m/$ro_filter/) {
		print $_[0];
		$tally_filtered++;
	}
	else { $tally_excluded++; }
}


sub print_report() {
	verboseprint("Records retained    : $tally_filtered");
	verboseprint("Records filtered out: $tally_excluded");
	verboseprint("Bad records dropped : $tally_bad");
	verboseprint("Total records       :", $tally_filtered + $tally_excluded + $tally_bad);
}

sub verboseprint() {
	print STDERR "[@_]\n" if $be_verbose;
}

sub debugprint() {
	print STDERR "<@_>\n" if $be_debuggin;
}

#EOF
