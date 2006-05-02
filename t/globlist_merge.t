#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 25;

sub same {
	my $a=shift;
	my $b=shift;
	my $match=shift;
	
	my $imatch=(IkiWiki::globlist_match($match, $a) ||
		    IkiWiki::globlist_match($match, $b));
	my $cmatch=IkiWiki::globlist_match($match, IkiWiki::globlist_merge($a, $b));
	
	return $imatch == $cmatch;
}

BEGIN { use_ok("IkiWiki::Render"); }

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
ok(same("* !foo", "!bar", "bar"), "matching glob and matching inversion");
ok(same("* !foo", "!bar", "foo"), "matching glob with matching inversion and non-matching inversion");
ok(same("* !foo", "!foo", "foo"), "matching glob with matching inversion and matching inversion");
ok(same("b??", "!b??", "bar"), "matching glob and matching inverted glob");
ok(same("f?? !f??", "!bar", "bar"), "matching glob and matching inverted glob");
ok(same("b??", "!b?z", "bar"), "matching glob and non-matching inverted glob");
ok(same("f?? !f?z", "!bar", "bar"), "matching glob and non-matching inverted glob");
ok(same("!foo bar baz", "!bar", "bar"), "matching list and matching inversion");
ok(IkiWiki::globlist_match("foo/Discussion",
	IkiWiki::globlist_merge("* !*/Discussion", "*/Discussion")), "should match");
ok(same("* !*/Discussion", "*/Discussion", "foo/Discussion"), "Discussion merge 1");
ok(same("*/Discussion", "* !*/Discussion", "foo/Discussion"), "Discussion merge 2");
ok(same("*/Discussion !*/bar", "*/bar !*/Discussion", "foo/Discussion"), "bidirectional merge 1");
ok(same("*/Discussion !*/bar", "*/bar !*/Discussion", "foo/bar"), "bidirectional merge 2");
