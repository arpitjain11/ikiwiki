#!/usr/bin/perl
use warnings;
use strict;
use Test::More 'no_plan';

ok(! system("mkdir t/tmp"));
ok(! system("make -s ikiwiki.out"));
ok(! system("make extra_install DESTDIR=`pwd`/t/tmp/install PREFIX=/usr >/dev/null"));
ok(! system("LC_ALL=C perl -T -I. ./ikiwiki.out -plugin smiley -plugin brokenlinks -rebuild -underlaydir=t/tmp/install/usr/share/ikiwiki/basewiki -templatedir=templates t/basewiki_brokenlinks t/tmp/out"));
my $result=`grep 'no broken links' t/tmp/out/index.html`;
ok(length($result));
if (! length $result) {
	print STDERR "broken links found:";
	system("grep '<li>' t/tmp/out/index.html >&2");
}
ok(-e "t/tmp/out/style.css");
ok(! system("rm -rf t/tmp t/basewiki_brokenlinks/.ikiwiki"));
