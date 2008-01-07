#!/usr/bin/perl
package IkiWiki::Plugin::opendiscussion;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "canedit", id => "opendiscussion", call => \&canedit);
} # }}}

sub canedit ($$) { #{{{
	my $page=shift;
	my $cgi=shift;
	my $session=shift;

	my $discussion=gettext("discussion");
	return "" if $page=~/(\/|^)\Q$discussion\E$/;
	return undef;
} #}}}

1
