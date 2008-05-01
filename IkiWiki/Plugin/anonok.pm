#!/usr/bin/perl
package IkiWiki::Plugin::anonok;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "canedit", id => "anonok", call => \&canedit,);
} # }}}

sub canedit ($$$) { #{{{
	my $page=shift;
	my $cgi=shift;
	my $session=shift;

	my $ret;

	if (length $config{anonok_pagespec}) {
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
} #}}}

1
