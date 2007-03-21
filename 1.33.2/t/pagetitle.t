#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 6;

BEGIN { use_ok("IkiWiki"); }

is(IkiWiki::pagetitle("foo_bar"), "foo bar");
is(IkiWiki::pagetitle("foo_bar_baz"), "foo bar baz");
is(IkiWiki::pagetitle("foo_bar__33__baz"), "foo bar&#33;baz");
is(IkiWiki::pagetitle("foo_bar__1234__baz"), "foo bar&#1234;baz");
is(IkiWiki::pagetitle("foo_bar___33___baz"), "foo bar &#33; baz");
