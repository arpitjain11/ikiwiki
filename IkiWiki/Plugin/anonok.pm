#!/usr/bin/perl
package IkiWiki::Plugin::anonok;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	hook(type => "canedit", id => "anonok", call => \&canedit,);
} # }}}

sub canedit ($$$) { #{{{
	return "";
} #}}}

1
