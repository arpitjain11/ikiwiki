#!/usr/bin/perl
# WikiCreole markup
# based on the WikiText plugin.
package IkiWiki::Plugin::creole;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "creole", call => \&getsetup);
	hook(type => "htmlize", id => "creole", call => \&htmlize);
}

sub getsetup {
	return
		plugin => {
			safe => 1,
			rebuild => 1, # format plugin
		},
}

sub htmlize (@) {
	my %params=@_;
	my $content = $params{content};

	eval q{use Text::WikiCreole};
	return $content if $@;

	# don't parse WikiLinks, ikiwiki already does
	creole_customlinks();
	creole_custombarelinks();

	return creole_parse($content);
}

1
