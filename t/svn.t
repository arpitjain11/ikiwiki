#!/usr/bin/perl
use warnings;
use strict;
my $dir;
BEGIN {
	$dir="/tmp/ikiwiki-test-svn.$$";
	my $svn=`which svn`;
	chomp $svn;
	my $svnadmin=`which svnadmin`;
	chomp $svnadmin;
	if (! -x $svn || ! -x $svnadmin || ! mkdir($dir)) {
		eval q{
			use Test::More skip_all => "svn not available or could not make test dir"
		}
	}
}
use Test::More tests => 12;

BEGIN { use_ok("IkiWiki"); }

%config=IkiWiki::defaultconfig();
$config{rcs} = "svn";
$config{srcdir} = "$dir/src";
$config{svnpath} = "trunk";
IkiWiki::checkconfig();

my $svnrepo = "$dir/repo";

system "svnadmin create $svnrepo >/dev/null";
system "svn mkdir file://$svnrepo/trunk -m add >/dev/null";
system "svn co file://$svnrepo/trunk $config{srcdir} >/dev/null";

# Web commit
my $test1 = readfile("t/test1.mdwn");
writefile('test1.mdwn', $config{srcdir}, $test1);
IkiWiki::rcs_add("test1.mdwn");
IkiWiki::rcs_commit("test1.mdwn", "Added the first page", "moo");

my @changes;
@changes = IkiWiki::rcs_recentchanges(3);

is($#changes, 0);
is($changes[0]{message}[0]{"line"}, "Added the first page");
is($changes[0]{pages}[0]{"page"}, "test1.mdwn");
	
# Manual commit
my $message = "Added the second page";

my $test2 = readfile("t/test2.mdwn");
writefile('test2.mdwn', $config{srcdir}, $test2);
system "svn add $config{srcdir}/test2.mdwn >/dev/null";
system "svn commit $config{srcdir}/test2.mdwn -m \"$message\" >/dev/null";

@changes = IkiWiki::rcs_recentchanges(3);
is($#changes, 1);
is($changes[0]{message}[0]{"line"}, $message);
is($changes[0]{pages}[0]{"page"}, "test2.mdwn");
is($changes[1]{pages}[0]{"page"}, "test1.mdwn");

# extra slashes in the path shouldn't break things
$config{svnpath} = "/trunk//";
IkiWiki::checkconfig();
@changes = IkiWiki::rcs_recentchanges(3);
is($#changes, 1);
is($changes[0]{message}[0]{"line"}, $message);
is($changes[0]{pages}[0]{"page"}, "test2.mdwn");
is($changes[1]{pages}[0]{"page"}, "test1.mdwn");

system "rm -rf $dir";
