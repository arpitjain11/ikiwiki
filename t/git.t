#!/usr/bin/perl
use warnings;
use strict;

my $dir;
my $gitrepo;
BEGIN {
	$dir="/tmp/ikiwiki-test-git.$$";
	$gitrepo="$dir/repo";
	my $git=`which git`;
	chomp $git;
	if (! -x $git || ! mkdir($dir) || ! mkdir($gitrepo)) {
		eval q{
			use Test::More skip_all => "git not available or could not make test dirs"
		}
	}
}
use Test::More tests => 16;

BEGIN { use_ok("IkiWiki"); }

%config=IkiWiki::defaultconfig();
$config{rcs} = "git";
$config{srcdir} = "$dir/src";
IkiWiki::checkconfig();

system "cd $gitrepo && git init >/dev/null 2>&1";
system "cd $gitrepo && echo dummy > dummy; git add . >/dev/null 2>&1";
system "cd $gitrepo && git commit -m Initial >/dev/null 2>&1";
system "git clone -l -s $gitrepo $config{srcdir} >/dev/null 2>&1";

my @changes;
@changes = IkiWiki::rcs_recentchanges(3);

is($#changes, 0); # counts for dummy commit during repo creation
is($changes[0]{message}[0]{"line"}, "Initial");
is($changes[0]{pages}[0]{"page"}, "dummy");

# Web commit
my $test1 = readfile("t/test1.mdwn");
writefile('test1.mdwn', $config{srcdir}, $test1);
IkiWiki::rcs_add("test1.mdwn");
IkiWiki::rcs_commit("test1.mdwn", "Added the first page", "moo");

@changes = IkiWiki::rcs_recentchanges(3);

is($#changes, 1);
is($changes[0]{message}[0]{"line"}, "Added the first page");
is($changes[0]{pages}[0]{"page"}, "test1.mdwn");
	
# Manual commit
my $message = "Added the second page";

my $test2 = readfile("t/test2.mdwn");
writefile('test2.mdwn', $config{srcdir}, $test2);
system "cd $config{srcdir}; git add test2.mdwn >/dev/null 2>&1";
system "cd $config{srcdir}; git commit -m \"$message\" test2.mdwn >/dev/null 2>&1";
system "cd $config{srcdir}; git push origin >/dev/null 2>&1";

@changes = IkiWiki::rcs_recentchanges(3);

is($#changes, 2);
is($changes[0]{message}[0]{"line"}, $message);
is($changes[0]{pages}[0]{"page"}, "test2.mdwn");

is($changes[1]{pages}[0]{"page"}, "test1.mdwn");

# Renaming

writefile('test3.mdwn', $config{srcdir}, $test1);
IkiWiki::rcs_add("test3.mdwn");
IkiWiki::rcs_rename("test3.mdwn", "test4.mdwn");
IkiWiki::rcs_commit_staged("Added the 4th page", "moo", "Joe User");

@changes = IkiWiki::rcs_recentchanges(4);

is($#changes, 3);
is($changes[0]{pages}[0]{"page"}, "test4.mdwn");

ok(mkdir($config{srcdir}."/newdir"));
IkiWiki::rcs_rename("test4.mdwn", "newdir/test5.mdwn");
IkiWiki::rcs_commit_staged("Added the 5th page", "moo", "Joe User");

@changes = IkiWiki::rcs_recentchanges(4);

is($#changes, 3);
is($changes[0]{pages}[0]{"page"}, "newdir/test5.mdwn");

IkiWiki::rcs_remove("newdir/test5.mdwn");
IkiWiki::rcs_commit_staged("Remove the 5th page", "moo", "Joe User");

system "rm -rf $dir";
