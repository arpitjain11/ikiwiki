#!/usr/bin/perl
# CamelCase links
package IkiWiki::Plugin::camelcase;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "filter", id => "camelcase", call => \&filter);
} # }}}

sub filter (@) { #{{{
	my %params=@_;

	# Make CamelCase links work by promoting them to fullfledged
	# WikiLinks. This regexp is based on the one in Text::WikiFormat.
	$params{content}=~s#(?<![[|"/>=])\b((?:[A-Z][a-z0-9]\w*){2,})#[[$1]]#g;

	return $params{content};
} #}}}

1
