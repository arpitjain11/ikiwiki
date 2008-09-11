#!/usr/bin/perl
use warnings;
use strict;
use Test::More 'no_plan';

ok(! system("rm -rf t/tmp; mkdir t/tmp"));
ok(! system("make -s ikiwiki.out"));
ok(! system("make extra_install DESTDIR=`pwd`/t/tmp/install PREFIX=/usr >/dev/null"));

foreach my $plugin ("", "listdirectives") {
	ok(! system("LC_ALL=C perl -T -I. ./ikiwiki.out -rebuild -plugin brokenlinks ".
			# always enabled because pages link to it conditionally,
			# which brokenlinks cannot handle properly
			"-plugin smiley ".
			($plugin ? "-plugin $plugin " : "").
			"-underlaydir=t/tmp/install/usr/share/ikiwiki/basewiki ".
			"-templatedir=templates t/basewiki_brokenlinks t/tmp/out"));
	my $result=`grep 'no broken links' t/tmp/out/index.html`;
	ok(length($result));
	if (! length $result) {
		print STDERR "\n\nbroken links found".($plugin ? " (with $plugin)" : "")."\n";
		system("grep '<li>' t/tmp/out/index.html >&2");
		print STDERR "\n\n";
	}
	ok(-e "t/tmp/out/style.css"); # linked to..
	ok(! system("rm -rf t/tmp/out t/basewiki_brokenlinks/.ikiwiki"));
}
ok(! system("rm -rf t/tmp"));
