#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 7;

BEGIN { use_ok("IkiWiki"); }

is(linkpage("foo bar"), "foo_bar");
is(linkpage("foo bar baz"), "foo_bar_baz");
is(linkpage("foo bar/baz"), "foo_bar/baz");
is(linkpage("foo bar&baz"), "foo_bar__38__baz");
is(linkpage("foo bar & baz"), "foo_bar___38___baz");
is(linkpage("foo bar_baz"), "foo_bar_baz");
