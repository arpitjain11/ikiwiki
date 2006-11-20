#!/usr/bin/perl
use warnings;
use strict;
use Test::More;

my @progs="ikiwiki.in";
my @libs="IkiWiki.pm";
push @libs, map { chomp; $_ } `find IkiWiki -type f -name \\*.pm`;

plan(tests => (@progs + @libs));

foreach my $file (@progs) {
        ok(system("perl -T -c $file >/dev/null 2>&1") eq 0, $file);
}
foreach my $file (@libs) {
        ok(system("perl -c $file >/dev/null 2>&1") eq 0, $file);
}
