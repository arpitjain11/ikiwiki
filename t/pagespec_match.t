#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 35;

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

$IkiWiki::links{foo}=[qw{bar baz}];
ok(IkiWiki::pagespec_match("foo", "link(bar)"));
ok(! IkiWiki::pagespec_match("foo", "link(quux)"));
ok(IkiWiki::pagespec_match("bar", "backlink(foo)"));
ok(! IkiWiki::pagespec_match("quux", "backlink(foo)"));

$IkiWiki::pagectime{foo}=1154532692; # Wed Aug  2 11:26 EDT 2006
$IkiWiki::pagectime{bar}=1154532695; # after
ok(IkiWiki::pagespec_match("foo", "created_before(bar)"));
ok(! IkiWiki::pagespec_match("foo", "created_after(bar)"));
ok(! IkiWiki::pagespec_match("bar", "created_before(foo)"));
ok(IkiWiki::pagespec_match("bar", "created_after(foo)"));
ok(IkiWiki::pagespec_match("foo", "creation_year(2006)"), "year");
ok(! IkiWiki::pagespec_match("foo", "creation_year(2005)"), "other year");
ok(IkiWiki::pagespec_match("foo", "creation_month(8)"), "month");
ok(! IkiWiki::pagespec_match("foo", "creation_month(9)"), "other month");
ok(IkiWiki::pagespec_match("foo", "creation_day(2)"), "day");
ok(! IkiWiki::pagespec_match("foo", "creation_day(3)"), "other day");

# old style globlists
ok(IkiWiki::pagespec_match("foo", "foo bar"), "simple list");
ok(IkiWiki::pagespec_match("bar", "foo bar"), "simple list 2");
ok(IkiWiki::pagespec_match("foo", "f?? !foz"));
ok(! IkiWiki::pagespec_match("foo", "f?? !foo"));
ok(! IkiWiki::pagespec_match("foo", "* !foo"));
ok(! IkiWiki::pagespec_match("foo", "foo !foo"));
ok(! IkiWiki::pagespec_match("foo.png", "* !*.*"));
