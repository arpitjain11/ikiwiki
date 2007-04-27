#!/usr/bin/perl

package IkiWiki::Plugin::typography;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	IkiWiki::hook(type => "sanitize", id => "typography", call => \&sanitize);
} # }}}

sub sanitize (@) { #{{{
	my %params=@_;

	eval q{use Text::Typography};
	return $params{content} if $@;

	return Text::Typography::typography($params{content});
} # }}}

1
