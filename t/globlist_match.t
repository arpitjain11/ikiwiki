#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 11;

BEGIN { use_ok("IkiWiki"); }
ok(IkiWiki::globlist_match("foo", "*"));
ok(IkiWiki::globlist_match("foo", "f?? !foz"));
ok(! IkiWiki::globlist_match("foo", "f?? !foo"));
ok(! IkiWiki::globlist_match("foo", "* !foo"));
ok(! IkiWiki::globlist_match("foo", "foo !foo"));
ok(IkiWiki::globlist_match("page", "?ag?"));
ok(! IkiWiki::globlist_match("page", "?a?g?"));
ok(! IkiWiki::globlist_match("foo.png", "* !*.*"));
ok(IkiWiki::globlist_match("foo.png", "*.*"));
ok(! IkiWiki::globlist_match("foo", "*.*"));
