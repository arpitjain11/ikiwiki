#!/usr/bin/perl
# hnb markup
# Licensed under the GPL v2 or greater
# Copyright (C) 2008 by Axel Beckert <abe@deuxchevaux.org>
# 
# TODO: Make a switch to allow both HTML export routines of hnb 
# (`export_html` and `export_htmlcss`) to be used.

package IkiWiki::Plugin::hnb;

use warnings;
use strict;
use IkiWiki 3.00;
use File::Temp qw(:mktemp);

sub import {
	hook(type => "getsetup", id => "hnb", call => \&getsetup);
	hook(type => "htmlize", id => "hnb", call => \&htmlize);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1, # format plugin
		},
}

sub htmlize (@) {
	my %params = @_;

	# hnb outputs version number etc. every time to STDOUT, so
	# using files makes it easier to seprarate.

	my $tmpin  = mkstemp( "/tmp/ikiwiki-hnbin.XXXXXXXXXX"  );
	my $tmpout = mkstemp( "/tmp/ikiwiki-hnbout.XXXXXXXXXX" );

	open(TMP, '>', $tmpin) or die "Can't write to $tmpin: $!";
	print TMP $params{content};
	close TMP;

	system("hnb '$tmpin' 'go root' 'export_html $tmpout' > /dev/null");
	unlink $tmpin;

	open(TMP, '<', $tmpout) or die "Can't read from $tmpout: $!";
	local $/;
	my $ret = <TMP>;
	close TMP;
	unlink $tmpout;

	$ret =~ s/.*<body>//si;
	$ret =~ s/<body>.*//si;

	return $ret;
}

1;
