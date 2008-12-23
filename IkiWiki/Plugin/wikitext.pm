#!/usr/bin/perl
# WikiText markup
package IkiWiki::Plugin::wikitext;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "wiki", call => \&getsetup);
	hook(type => "htmlize", id => "wiki", call => \&htmlize);
}

sub getsetup () {
	return
		plugin => {
			safe => 0, # format plugin
			rebuild => undef,
		},
}


sub htmlize (@) {
	my %params=@_;
	my $content = $params{content};

	eval q{use Text::WikiFormat};
	return $content if $@;
	return Text::WikiFormat::format($content, undef, { implicit_links => 0 });
}

1
