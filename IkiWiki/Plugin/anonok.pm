#!/usr/bin/perl
package IkiWiki::Plugin::anonok;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "anonok", call => \&getsetup);
	hook(type => "canedit", id => "anonok", call => \&canedit);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
		},
		anonok_pagespec => {
			type => "pagespec",
			example => "*/discussion",
			description => "PageSpec to limit which pages anonymous users can edit",
			link => "ikiwiki/PageSpec",
			safe => 1,
			rebuild => 0,
		},
}

sub canedit ($$$) {
	my $page=shift;
	my $cgi=shift;
	my $session=shift;

	my $ret;

	if (exists $config{anonok_pagespec} && length $config{anonok_pagespec}) {
		if (pagespec_match($page, $config{anonok_pagespec},
		                   location => $page)) {
			return "";
		}
		else {
			return undef;
		}
	}
	else {
		return "";
	}
}

1
