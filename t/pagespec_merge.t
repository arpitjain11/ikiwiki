#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 25;

BEGIN { use_ok("IkiWiki"); }

sub same {
	my $a=shift;
	my $b=shift;
	my $match=shift;
	
	my $imatch=(pagespec_match($match, $a) ||
		    pagespec_match($match, $b));
	my $cmatch=pagespec_match($match, IkiWiki::pagespec_merge($a, $b));
	
	return $imatch == $cmatch;
}

ok(same("foo", "bar", "foo"), "basic match 1");
ok(same("foo", "bar", "bar"), "basic match 2");
ok(same("foo", "bar", "foobar"), "basic failed match");
ok(same("foo", "!bar", "foo"), "basic match with inversion");
ok(same("foo", "!bar", "bar"), "basic failed match with inversion");
ok(same("!foo", "bar", "foo"), "basic failed match with inversion 2");
ok(same("!foo", "bar", "bar"), "basic match with inversion 2");
ok(same("!foo", "!bar", "foo"), "double inversion failed match");
ok(same("!foo", "!bar", "bar"), "double inversion failed match 2");
ok(same("*", "!bar", "foo"), "glob+inversion match");
ok(same("*", "!bar", "bar"), "matching glob and matching inversion");
ok(same("* and !foo", "!bar", "bar"), "matching glob and matching inversion");
ok(same("* and !foo", "!bar", "foo"), "matching glob with matching inversion and non-matching inversion");
ok(same("* and !foo", "!foo", "foo"), "matching glob with matching inversion and matching inversion");
ok(same("b??", "!b??", "bar"), "matching glob and matching inverted glob");
ok(same("f?? !f??", "!bar", "bar"), "matching glob and matching inverted glob");
ok(same("b??", "!b?z", "bar"), "matching glob and non-matching inverted glob");
ok(same("f?? !f?z", "!bar", "bar"), "matching glob and non-matching inverted glob");
ok(same("!foo bar baz", "!bar", "bar"), "matching list and matching inversion");
ok(pagespec_match("foo/Discussion",
	IkiWiki::pagespec_merge("* and !*/Discussion", "*/Discussion")), "should match");
ok(same("* and !*/Discussion", "*/Discussion", "foo/Discussion"), "Discussion merge 1");
ok(same("*/Discussion", "* and !*/Discussion", "foo/Discussion"), "Discussion merge 2");
ok(same("*/Discussion !*/bar", "*/bar !*/Discussion", "foo/Discussion"), "bidirectional merge 1");
ok(same("*/Discussion !*/bar", "*/bar !*/Discussion", "foo/bar"), "bidirectional merge 2");
