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
use Test::More tests => 11;

BEGIN { use_ok("IkiWiki"); }

%config=IkiWiki::defaultconfig();
$config{rcs} = "git";
$config{srcdir} = "$dir/src";
IkiWiki::checkconfig();

system "cd $gitrepo && git init-db 2>/dev/null";
system "cd $gitrepo && echo dummy >dummy; git add . 2>/dev/null";
system "cd $gitrepo && git commit -m Initial 2>/dev/null";
system "git clone -l -s $gitrepo $config{srcdir} 2>/dev/null";

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
system "cd $config{srcdir}; git add test2.mdwn 2>/dev/null";
system "cd $config{srcdir}; git commit -m \"$message\" test2.mdwn 2>/dev/null";
system "cd $config{srcdir}; git push origin 2>/dev/null";

@changes = IkiWiki::rcs_recentchanges(3);

is($#changes, 2);
is($changes[0]{message}[0]{"line"}, $message);
is($changes[0]{pages}[0]{"page"}, "test2.mdwn");

is($changes[1]{pages}[0]{"page"}, "test1.mdwn");

system "rm -rf $dir";
