#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 9;

BEGIN { use_ok("IkiWiki"); }

sub test ($$$) {
	my $page=shift;
	my $link=shift;
	my @existing_pages=@{shift()};
	
	%IkiWiki::pagecase=();
	%links=();
	foreach my $page (@existing_pages) {
		$IkiWiki::pagecase{lc $page}=$page;
		$links{$page}=[];
	}

	return bestlink($page, $link);
}

is(test("bar", "foo", ["bar"]), "", "broken link");
is(test("bar", "foo", ["bar", "foo"]), "foo", "simple link");
is(test("bar", "FoO", ["bar", "foo"]), "foo", "simple link with different input case");
is(test("bar", "foo", ["bar", "fOo"]), "fOo", "simple link with different page case");
is(test("bar", "FoO", ["bar", "fOo"]), "fOo", "simple link with different page and input case");
is(test("bar", "Foo", ["bar", "fOo", "foo", "fOO", "Foo", "fOo"]), "Foo", "in case of ambiguity, like case wins");
is(test("bar", "foo", ["bar", "foo", "bar/foo"]), "bar/foo", "simple subpage link");
is(test("bar", "foo/subpage", ["bar", "foo", "bar/subpage", "foo/subpage"]), "foo/subpage", "cross subpage link");
