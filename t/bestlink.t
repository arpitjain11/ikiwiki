#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 5;

sub test ($$$) {
	my $page=shift;
	my $link=shift;
	my @existing_pages=@{shift()};
	
	%IkiWiki::links=();
	foreach my $page (@existing_pages) {
		$IkiWiki::links{$page}=[];
	}

	return IkiWiki::bestlink($page, $link);
}

BEGIN { use_ok("IkiWiki"); }

is(test("bar", "foo", ["bar"]), "", "broken link");
is(test("bar", "foo", ["bar", "foo"]), "foo", "simple link");
is(test("bar", "foo", ["bar", "foo", "bar/foo"]), "bar/foo", "simple subpage link");
is(test("bar", "foo/subpage", ["bar", "foo", "bar/subpage", "foo/subpage"]), "foo/subpage", "cross subpage link");
