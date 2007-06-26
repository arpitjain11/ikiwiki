#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 3;

ok(! system("make ikiwiki.out"));
ok(! system("perl -T -I. ./ikiwiki.out -plugin brokenlinks -rebuild -underlaydir=basewiki -templatedir=templates t/basewiki_brokenlinks t/basewiki_brokenlinks/out"));
ok(`grep 'no broken links' t/basewiki_brokenlinks/out/index.html`);
system("rm -rf t/basewiki_brokenlinks/out t/basewiki_brokenlinks/.ikiwiki");
