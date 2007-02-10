#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 6;

BEGIN { use_ok("IkiWiki"); }

is(IkiWiki::basename("/home/joey/foo/bar"), "bar");
is(IkiWiki::basename("./foo"), "foo");
is(IkiWiki::basename("baz"), "baz");
is(IkiWiki::basename("/tmp/"), "");
is(IkiWiki::basename("/home/joey/foo/"), "");
