#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 7;

BEGIN { use_ok("IkiWiki"); }

is(titlepage("foo bar"), "foo_bar");
is(titlepage("foo bar baz"), "foo_bar_baz");
is(titlepage("foo bar/baz"), "foo_bar/baz");
is(titlepage("foo bar&baz"), "foo_bar__38__baz");
is(titlepage("foo bar & baz"), "foo_bar___38___baz");
is(titlepage("foo bar_baz"), "foo_bar__95__baz");
