#!/usr/bin/perl
# Include a fortune in a page
package IkiWiki::Plugin::fortune;

use warnings;
use strict;

sub import { #{{{
	IkiWiki::hook(type => "preprocess", id => "fortune",
		call => \&preprocess);
} # }}}

sub preprocess (@) { #{{{
	$ENV{PATH}="$ENV{PATH}:/usr/games:/usr/local/games";
	my $f = `fortune`;

	if ($?) {
		return "[[fortune failed]]";
	}
	else {
		return "<pre>$f</pre>\n";
	}
} # }}}

1
