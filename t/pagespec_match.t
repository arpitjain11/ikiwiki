#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 41;

BEGIN { use_ok("IkiWiki"); }

ok(pagespec_match("foo", "*", ""));
ok(pagespec_match("page", "?ag?", ""));
ok(! pagespec_match("page", "?a?g?", ""));
ok(pagespec_match("foo.png", "*.*", ""));
ok(! pagespec_match("foo", "*.*", ""));
ok(pagespec_match("foo", "foo or bar", ""), "simple list");
ok(pagespec_match("bar", "foo or bar", ""), "simple list 2");
ok(pagespec_match("foo", "f?? and !foz", ""));
ok(! pagespec_match("foo", "f?? and !foo", ""));
ok(! pagespec_match("foo", "* and !foo", ""));
ok(! pagespec_match("foo", "foo and !foo", ""));
ok(! pagespec_match("foo.png", "* and !*.*", ""));
ok(pagespec_match("foo", "(bar or ((meep and foo) or (baz or foo) or beep))", ""));
ok(! pagespec_match("a/foo", "foo", "a/b"), "nonrelative fail");
ok(! pagespec_match("foo", "./*", "a/b"), "relative fail");
ok(pagespec_match("a/foo", "./*", "a/b"), "relative");
ok(pagespec_match("a/b/foo", "./*", "a/b"), "relative 2");
ok(pagespec_match("foo", "./*", "a"), "relative toplevel");
ok(pagespec_match("foo/bar", "*", "baz"), "absolute");

$links{foo}=[qw{bar baz}];
ok(pagespec_match("foo", "link(bar)", ""));
ok(! pagespec_match("foo", "link(quux)", ""));
ok(pagespec_match("bar", "backlink(foo)", ""));
ok(! pagespec_match("quux", "backlink(foo)", ""));

$IkiWiki::pagectime{foo}=1154532692; # Wed Aug  2 11:26 EDT 2006
$IkiWiki::pagectime{bar}=1154532695; # after
ok(pagespec_match("foo", "created_before(bar)"));
ok(! pagespec_match("foo", "created_after(bar)"));
ok(! pagespec_match("bar", "created_before(foo)"));
ok(pagespec_match("bar", "created_after(foo)"));
ok(pagespec_match("foo", "creation_year(2006)"), "year");
ok(! pagespec_match("foo", "creation_year(2005)"), "other year");
ok(pagespec_match("foo", "creation_month(8)"), "month");
ok(! pagespec_match("foo", "creation_month(9)"), "other month");
ok(pagespec_match("foo", "creation_day(2)"), "day");
ok(! pagespec_match("foo", "creation_day(3)"), "other day");

# old style globlists
ok(pagespec_match("foo", "foo bar"), "simple list");
ok(pagespec_match("bar", "foo bar"), "simple list 2");
ok(pagespec_match("foo", "f?? !foz"));
ok(! pagespec_match("foo", "f?? !foo"));
ok(! pagespec_match("foo", "* !foo"));
ok(! pagespec_match("foo", "foo !foo"));
ok(! pagespec_match("foo.png", "* !*.*"));
