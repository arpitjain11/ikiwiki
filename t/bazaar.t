#!/usr/bin/perl
use warnings;
use strict;
my $dir;
BEGIN {
	$dir = "/tmp/ikiwiki-test-bzr.$$";
	my $bzr=`which bzr`;
	chomp $bzr;
	if (! -x $bzr || ! mkdir($dir)) {
		eval q{
			use Test::More skip_all => "bzr not available or could not make test dir"
		}
	}
}
use Test::More tests => 16;

BEGIN { use_ok("IkiWiki"); }

%config=IkiWiki::defaultconfig();
$config{rcs} = "bzr";
$config{srcdir} = "$dir/repo";
IkiWiki::checkconfig();

system "bzr init $config{srcdir}";

# Web commit
my $test1 = readfile("t/test1.mdwn");
writefile('test1.mdwn', $config{srcdir}, $test1);
IkiWiki::rcs_add("test1.mdwn");
IkiWiki::rcs_commit("test1.mdwn", "Added the first page", "moo", "Joe User");

my @changes;
@changes = IkiWiki::rcs_recentchanges(3);

is($#changes, 0);
is($changes[0]{message}[0]{"line"}, "Added the first page");
is($changes[0]{pages}[0]{"page"}, "test1.mdwn");
is($changes[0]{user}, "Joe User");
	
# Manual commit
my $username = "Foo Bar";
my $user = "$username <foo.bar\@example.com>";
my $message = "Added the second page";

my $test2 = readfile("t/test2.mdwn");
writefile('test2.mdwn', $config{srcdir}, $test2);
system "bzr add --quiet $config{srcdir}/test2.mdwn";
system "bzr commit --quiet --author \"$user\" -m \"$message\" $config{srcdir}";
	
@changes = IkiWiki::rcs_recentchanges(3);

is($#changes, 1);
is($changes[0]{message}[0]{"line"}, $message);
is($changes[0]{user}, $username);
is($changes[0]{pages}[0]{"page"}, "test2.mdwn");

is($changes[1]{pages}[0]{"page"}, "test1.mdwn");

my $ctime = IkiWiki::rcs_getctime("test2.mdwn");
ok($ctime >= time() - 20);

writefile('test3.mdwn', $config{srcdir}, $test1);
IkiWiki::rcs_add("test3.mdwn");
IkiWiki::rcs_rename("test3.mdwn", "test4.mdwn");
IkiWiki::rcs_commit_staged("Added the 4th page", "moo", "Joe User");

@changes = IkiWiki::rcs_recentchanges(4);

is($#changes, 2);
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
