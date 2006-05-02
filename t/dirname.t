#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 6;

BEGIN { use_ok("IkiWiki"); }

is(IkiWiki::dirname("/home/joey/foo/bar"), "/home/joey/foo");
is(IkiWiki::dirname("./foo"), ".");
is(IkiWiki::dirname("baz"), "");
is(IkiWiki::dirname("/tmp/"), "/tmp/");
is(IkiWiki::dirname("/home/joey/foo/"), "/home/joey/foo/");
