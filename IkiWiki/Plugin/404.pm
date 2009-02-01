#!/usr/bin/perl
# Copyright © 2009 Simon McVittie <http://smcv.pseudorandom.co.uk/>
# Licensed under the GNU GPL, version 2, or any later version published by the
# Free Software Foundation
package IkiWiki::Plugin::404;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "cgi", id => '404',  call => \&cgi);
	IkiWiki::loadplugin("goto");
}

sub getsetup () {
	return
		plugin => {
			# not really a matter of safety, but enabling/disabling
			# through a web interface is useless - it needs web
			# server admin action too
			safe => 0,
			rebuild => 0,
		}
}

sub cgi_page_from_404 ($$$) {
	my $path = shift;
	my $baseurl = shift;
	my $usedirs = shift;

	# fail if missing from environment or whatever
	return undef unless defined $path;
	return undef unless defined $baseurl;

	# with usedirs on, path is like /~fred/foo/bar/ or /~fred/foo/bar or
	#    /~fred/foo/bar/index.html
	# with usedirs off, path is like /~fred/foo/bar.html
	# baseurl is like 'http://people.example.com/~fred'

	# convert baseurl to ~fred
	unless ($baseurl =~ s{^https?://[^/]+/?}{}) {
		return undef;
	}

	# convert path to /~fred/foo/bar
	if ($usedirs) {
		$path =~ s/\/*(?:index\.$config{htmlext})?$//;
	}
	else {
		$path =~ s/\.$config{htmlext}$//;
	}

	# remove /~fred/
	unless ($path =~ s{^/*\Q$baseurl\E/*}{}) {
		return undef;
	}

	# special case for the index
	unless ($path) {
		return 'index';
	}

	return $path;
}

sub cgi ($) {
	my $cgi=shift;

	if ($ENV{REDIRECT_STATUS} eq '404') {
		my $page = cgi_page_from_404($ENV{REDIRECT_URL},
			$config{url}, $config{usedirs});
		IkiWiki::Plugin::goto::cgi_goto($cgi, $page);
	}
}

1;
