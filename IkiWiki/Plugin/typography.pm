#!/usr/bin/perl

package IkiWiki::Plugin::typography;

use warnings;
use strict;
use IkiWiki;
use Text::Typography;

sub import { #{{{
	IkiWiki::hook(type => "sanitize", id => "typography", call => \&sanitize);
} # }}}

sub sanitize (@) { #{{{
	my %params=@_;

	return Text::Typography::typography($params{content});
} # }}}

1
