#!/usr/bin/perl
# Include a fortune in a page
package IkiWiki::Plugin::fortune;

use IkiWiki;
use warnings;
use strict;

sub import { #{{{
	hook(type => "preprocess", id => "fortune", call => \&preprocess);
} # }}}

sub preprocess (@) { #{{{
	$ENV{PATH}="$ENV{PATH}:/usr/games:/usr/local/games";
	my $f = `fortune 2>/dev/null`;

	if ($?) {
		return "[[fortune failed]]";
	}
	else {
		return "<pre>$f</pre>\n";
	}
} # }}}

1
