#!/usr/bin/perl
#
# Include polygen output in a page
# 
# by Enrico Zini
package IkiWiki::Plugin::polygen;

use warnings;
use strict;
use IkiWiki 3.00;
use File::Find;

sub import {
	hook(type => "getsetup", id => "polygen", call => \&getsetup);
	hook(type => "preprocess", id => "polygen", call => \&preprocess);
}

sub getsetup () {
	return 
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess (@) {
	my %params=@_;
	my $grammar = ($params{grammar} or 'polygen');
	my $symbol = ($params{symbol} or undef);

	# Sanitize parameters
	$grammar =~ IkiWiki::basename($grammar);
	$grammar =~ s/[^A-Za-z0-9]//g;
	$grammar =~ s/\.grm$//;
	$grammar .= '.grm';
	$symbol =~ s/[^A-Za-z0-9]//g if defined $symbol;
	$symbol = IkiWiki::possibly_foolish_untaint($symbol) if defined $symbol;

	my $grmfile = '/usr/share/polygen/ita/polygen.grm';
	if (! -d '/usr/share/polygen') {
		error gettext("polygen not installed");
	}
	find({wanted => sub {
			if (substr($File::Find::name, -length($grammar)) eq $grammar) {
				$grmfile = IkiWiki::possibly_foolish_untaint($File::Find::name);
			}
		},
		no_chdir => 1,
	}, '/usr/share/polygen');
	
	my $res;
	if (defined $symbol) {
		$res = `polygen -S $symbol $grmfile 2>/dev/null`;
	}
	else {
		$res = `polygen $grmfile 2>/dev/null`;
	}

	if ($?) {
		error gettext("command failed");
	}

	# Strip trailing spaces and newlines so that we flow well with the
	# markdown text
	$res =~ s/\s*$//;
	return $res;
}

1
