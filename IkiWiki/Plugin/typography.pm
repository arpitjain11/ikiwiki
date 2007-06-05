#!/usr/bin/perl

package IkiWiki::Plugin::typography;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "getopt", id => "typography", call => \&getopt);
	IkiWiki::hook(type => "sanitize", id => "typography", call => \&sanitize);
} # }}}

sub getopt () { #{{{
	eval q{use Getopt::Long};
	error($@) if $@;
	Getopt::Long::Configure('pass_through');
	GetOptions("typographyattributes=s" => \$config{typographyattributes});
} #}}}

sub sanitize (@) { #{{{
	my %params=@_;

	eval q{use Text::Typography};
	return $params{content} if $@;

	my $attributes=defined $config{typographyattributes} ? $config{typographyattributes} : '3';
	return Text::Typography::typography($params{content}, $attributes);
} # }}}

1
