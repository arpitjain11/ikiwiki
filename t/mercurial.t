#!/usr/bin/perl
use warnings;
use strict;
my $dir;
BEGIN {
	$dir = "/tmp/ikiwiki-test-hg.$$";
	my $hg=`which hg`;
	chomp $hg;
	if (! -x $hg || ! mkdir($dir)) {
		eval q{
			use Test::More skip_all => "hg not available or could not make test dir"
		}
	}
}
use Test::More tests => 11;

BEGIN { use_ok("IkiWiki"); }

%config=IkiWiki::defaultconfig();
$config{rcs} = "mercurial";
$config{srcdir} = "$dir/repo";
IkiWiki::loadplugins();
IkiWiki::checkconfig();

system "hg init $config{srcdir}";

# Web commit
my $test1 = readfile("t/test1.mdwn");
writefile('test1.mdwn', $config{srcdir}, $test1);
IkiWiki::rcs_add("test1.mdwn");
IkiWiki::rcs_commit("test1.mdwn", "Added the first page", "moo", "Joe User");

my @changes;
@changes = IkiWiki::rcs_recentchanges(3);

is($#changes, 0);
is($changes[0]{message}[0]{"line"}, "Added the first page");
is($changes[0]{pages}[0]{"page"}, "test1");
is($changes[0]{user}, "Joe User");
	
# Manual commit
my $username = "Foo Bar";
my $user = "$username <foo.bar\@example.com>";
my $message = "Added the second page";

my $test2 = readfile("t/test2.mdwn");
writefile('test2.mdwn', $config{srcdir}, $test2);
system "hg add -R $config{srcdir} $config{srcdir}/test2.mdwn";
system "hg commit -R $config{srcdir} -u \"$user\" -m \"$message\" -d \"0 0\"";
	
@changes = IkiWiki::rcs_recentchanges(3);

is($#changes, 1);
is($changes[0]{message}[0]{"line"}, $message);
is($changes[0]{user}, $username);
is($changes[0]{pages}[0]{"page"}, "test2");

is($changes[1]{pages}[0]{"page"}, "test1");

my $ctime = IkiWiki::rcs_getctime("test2.mdwn");
is($ctime, 0);

system "rm -rf $dir";
