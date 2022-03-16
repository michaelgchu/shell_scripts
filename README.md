# shell_scripts
A collection of shell scripts that others may find useful.  Developed for Linux; Cygwin compatibility is unknown.

## text_file_analysis
The latest addition is a record filtering script **"rrfilter.pl"**. It's like a mix of grep and csvkit's csvgrep:
- processes multiline records like csvgrep can (think: CSV files with fields wrapped in double-quotes and contain embedded line breaks)
- does not modify the data that it passes through unless additional switches are applied (e.g. a tab-delimited file will remain as tab-delimited)
- it can filter on a specific field or the entire record

As a Perl program, it of course uses regular expressions to perform the filtering! Here is a sample call that will select records for which the second field ends with a "word" that ends in a vowel and does not contain the letter L:

<pre>
$ cat -n good2_bad2.csv 
     1  Col1,Col2,"Col3"
     2  first,second,third
     3  A,"The ""cake"", is, a, lie",C
     4  too,many,fields,in,this,line
     5  This,"record has a
     6  line break-No joke","and that's ok!"
     7  too,"few fields"
$ rrfilter.pl -c 2 -i '\b(?:(?!l)\w)+[aeiouy]$' good2_bad2.csv 
Col1,Col2,"Col3"
This,"record has a
line break-No joke","and that's ok!"
</pre>
