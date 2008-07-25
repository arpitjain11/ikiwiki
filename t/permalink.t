#!/usr/bin/perl
use warnings;
use strict;
use Test::More 'no_plan';

ok(! system("mkdir t/tmp"));
ok(! system("make -s ikiwiki.out"));
ok(! system("LC_ALL=C perl -T -I. ./ikiwiki.out -plugin inline -url=http://example.com -cgiurl=http://example.com/ikiwiki.cgi -rss -atom -underlaydir=underlays/basewiki -templatedir=templates t/tinyblog t/tmp/out"));
# This guid should never, ever change, for any reason whatsoever!
my $guid="http://example.com/post/";
ok(length `grep '<guid>$guid</guid>' t/tmp/out/index.rss`);
ok(length `grep '<id>$guid</id>' t/tmp/out/index.atom`);
ok(! system("rm -rf t/tmp t/tinyblog/.ikiwiki"));
