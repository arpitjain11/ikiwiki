#!/usr/bin/perl
package IkiWiki::Plugin::signinedit;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	hook(type => "canedit", id => "signinedit", call => \&canedit,
	     last => 1);
} # }}}

sub canedit ($$$) { #{{{
	my $page=shift;
	my $cgi=shift;
	my $session=shift;

	# Have the user sign in, if they are not already. This is why the
	# hook runs last, so that any hooks that don't need the user to
	# signin can override this.
	IkiWiki::needsignin($cgi, $session);
	return "";
} #}}}

1
