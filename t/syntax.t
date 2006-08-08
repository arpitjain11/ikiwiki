#!/usr/bin/perl
use warnings;
use strict;
use Test;

my @progs="ikiwiki.pl";
my @libs="IkiWiki.pm";
push @libs, map { chomp; $_ } `find IkiWiki -type f -name \\*.pm`;

plan(tests => (@progs + @libs));

foreach my $file (@progs) {
        print "# Testing $file\n";
        ok(system("perl -T -c $file >/dev/null 2>&1"), 0);
}
foreach my $file (@libs) {
        print "# Testing $file\n";
        ok(system("perl -c $file >/dev/null 2>&1"), 0);
}
