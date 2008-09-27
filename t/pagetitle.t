#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 7;

BEGIN { use_ok("IkiWiki"); }

is(pagetitle("foo_bar"), "foo bar");
is(pagetitle("foo_bar_baz"), "foo bar baz");
is(pagetitle("foo_bar__33__baz"), "foo bar&#33;baz");
is(pagetitle("foo_bar__1234__baz"), "foo bar&#1234;baz");
is(pagetitle("foo_bar___33___baz"), "foo bar &#33; baz");
is(pagetitle("foo_bar___95___baz"), "foo bar &#95; baz");
