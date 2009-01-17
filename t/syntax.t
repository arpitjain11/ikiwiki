#!/usr/bin/perl
use warnings;
use strict;
use Test::More;

my @progs="ikiwiki.in";
my @libs="IkiWiki.pm";
# monotone, external, blogspam, amazon_s3, po skipped since they need perl modules
push @libs, map { chomp; $_ } `find IkiWiki -type f -name \\*.pm | grep -v monotone.pm | grep -v external.pm | grep -v blogspam.pm | grep -v amazon_s3.pm | grep -v po.pm`;
push @libs, 'IkiWiki/Plugin/skeleton.pm.example';

plan(tests => (@progs + @libs));

foreach my $file (@progs) {
        ok(system("perl -T -c $file >/dev/null 2>&1") eq 0, $file);
}
foreach my $file (@libs) {
        ok(system("perl -c $file >/dev/null 2>&1") eq 0, $file);
}
