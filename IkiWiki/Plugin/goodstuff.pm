#!/usr/bin/perl
# Bundle of good stuff.
package IkiWiki::Plugin::goodstuff;

use warnings;
use strict;
use IkiWiki 3.00;

my @bundle=qw{
	brokenlinks
	img
	map
	more
	orphans
	pagecount
	pagestats
	progress
	shortcut
	smiley
	tag
	table
	template
	toc
	toggle
	repolist
};

sub import {
	hook(type => "getsetup", id => "goodstuff", call => \&getsetup);
	foreach my $plugin (@bundle) {
		IkiWiki::loadplugin($plugin);
	}
}

sub getsetup {
	return 
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

1
