#!/usr/bin/perl
# favicon plugin.

package IkiWiki::Plugin::favicon;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "favicon", call => \&getsetup);
	hook(type => "pagetemplate", id => "favicon", call => \&pagetemplate);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
}

sub pagetemplate (@) {
	my %params=@_;

	my $template=$params{template};
	
	if ($template->query(name => "favicon")) {
		$template->param(favicon => "favicon.ico");
	}
}

1
