#!/usr/bin/perl

package IkiWiki::Plugin::typography;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getopt", id => "typography", call => \&getopt);
	hook(type => "getsetup", id => "typography", call => \&getsetup);
	IkiWiki::hook(type => "sanitize", id => "typography", call => \&sanitize);
}

sub getopt () {
	eval q{use Getopt::Long};
	error($@) if $@;
	Getopt::Long::Configure('pass_through');
	GetOptions("typographyattributes=s" => \$config{typographyattributes});
}

sub getsetup () {
	eval q{use Text::Typography};
	error($@) if $@;

	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
		typographyattributes => {
			type => "string",
			example => "3",
			description => "Text::Typography attributes value",
			advanced => 1,
			safe => 1,
			rebuild => 1,
		},
}

sub sanitize (@) {
	my %params=@_;

	eval q{use Text::Typography};
	return $params{content} if $@;

	my $attributes=defined $config{typographyattributes} ? $config{typographyattributes} : '3';
	return Text::Typography::typography($params{content}, $attributes);
}

1
