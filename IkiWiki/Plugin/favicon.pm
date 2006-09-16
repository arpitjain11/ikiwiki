#!/usr/bin/perl
# favicon plugin.

package IkiWiki::Plugin::favicon;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	hook(type => "pagetemplate", id => "favicon", call => \&pagetemplate);
} # }}}

sub pagetemplate (@) { #{{{
	my %params=@_;

	my $template=$params{template};
	
	if ($template->query(name => "favicon")) {
		$template->param(favicon => "favicon.png");
	}
} # }}}

1
