#!/usr/bin/perl
# Bundle of good stuff.
package IkiWiki::Plugin::goodstuff;

use warnings;
use strict;
use IkiWiki 2.00;

my @bundle=qw{
	brokenlinks
	img
	map
	meta
	orphans
	pagecount
	pagestats
	shortcut
	smiley
	tag
	template
	toc
	toggle
	otl
};

sub import { #{{{
	hook(type => "getsetup", id => "goodstuff", call => \&getsetup);
	IkiWiki::loadplugin($_) foreach @bundle;
} # }}}

sub getsetup { #{{{
	return 
		plugin => {
			safe => 1,
			rebuild => undef,
		},
} #}}}

1
