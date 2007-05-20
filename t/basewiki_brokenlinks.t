#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 2;

my $ret=system("./ikiwiki.out -plugin brokenlinks -rebuild -underlaydir=basewiki t/basewiki_brokenlinks t/basewiki_brokenlinks/out");
ok($ret == 0);
ok(`grep 'no broken links' t/basewiki_brokenlinks/out/index.html`);
system("rm -rf t/basewiki_brokenlinks/out t/basewiki_brokenlinks/.ikiwiki");
