#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 7;

BEGIN { use_ok("IkiWiki"); }

is(IkiWiki::titlepage("foo bar"), "foo_bar");
is(IkiWiki::titlepage("foo bar baz"), "foo_bar_baz");
is(IkiWiki::titlepage("foo bar/baz"), "foo_bar/baz");
is(IkiWiki::titlepage("foo bar&baz"), "foo_bar__38__baz");
is(IkiWiki::titlepage("foo bar & baz"), "foo_bar___38___baz");
is(IkiWiki::titlepage("foo bar_baz"), "foo_bar__95__baz");
