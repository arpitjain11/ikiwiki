#!/usr/bin/perl
package IkiWiki::Plugin::nicebundle;

use warnings;
use strict;
use IkiWiki;

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
	IkiWiki::loadplugin($_) foreach @bundle;
} # }}}

1
