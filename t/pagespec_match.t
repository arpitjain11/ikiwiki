#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 21;

BEGIN { use_ok("IkiWiki"); }

ok(IkiWiki::pagespec_match("foo", "*"));
ok(IkiWiki::pagespec_match("page", "?ag?"));
ok(! IkiWiki::pagespec_match("page", "?a?g?"));
ok(IkiWiki::pagespec_match("foo.png", "*.*"));
ok(! IkiWiki::pagespec_match("foo", "*.*"));
ok(IkiWiki::pagespec_match("foo", "foo or bar"), "simple list");
ok(IkiWiki::pagespec_match("bar", "foo or bar"), "simple list 2");
ok(IkiWiki::pagespec_match("foo", "f?? and !foz"));
ok(! IkiWiki::pagespec_match("foo", "f?? and !foo"));
ok(! IkiWiki::pagespec_match("foo", "* and !foo"));
ok(! IkiWiki::pagespec_match("foo", "foo and !foo"));
ok(! IkiWiki::pagespec_match("foo.png", "* and !*.*"));
ok(IkiWiki::pagespec_match("foo", "(bar or ((meep and foo) or (baz or foo) or beep))"));

# old style globlists
ok(IkiWiki::pagespec_match("foo", "foo bar"), "simple list");
ok(IkiWiki::pagespec_match("bar", "foo bar"), "simple list 2");
ok(IkiWiki::pagespec_match("foo", "f?? !foz"));
ok(! IkiWiki::pagespec_match("foo", "f?? !foo"));
ok(! IkiWiki::pagespec_match("foo", "* !foo"));
ok(! IkiWiki::pagespec_match("foo", "foo !foo"));
ok(! IkiWiki::pagespec_match("foo.png", "* !*.*"));
