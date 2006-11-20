#!/usr/bin/perl
# HTTP basic auth plugin.
package IkiWiki::Plugin::httpauth;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	hook(type => "auth", id => "httpauth", call => \&auth);
} # }}}

sub auth ($$) { #{{{
	my $cgi=shift;
	my $session=shift;

	if (defined $cgi->remote_user()) {
		$session->param("name", $cgi->remote_user());
	}
} #}}}

1
