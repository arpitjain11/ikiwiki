#!/usr/bin/perl
# Include a fortune in a page
package IkiWiki::Plugin::fortune;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "fortune", call => \&getsetup);
	hook(type => "preprocess", id => "fortune", call => \&preprocess);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess (@) {
	$ENV{PATH}="$ENV{PATH}:/usr/games:/usr/local/games";
	my $f = `fortune 2>/dev/null`;

	if ($?) {
		error gettext("fortune failed");
	}
	else {
		return "<pre>$f</pre>\n";
	}
}

1
