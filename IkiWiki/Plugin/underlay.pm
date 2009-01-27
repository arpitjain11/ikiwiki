#!/usr/bin/perl
package IkiWiki::Plugin::underlay;
# Copyright © 2008 Simon McVittie <http://smcv.pseudorandom.co.uk/>
# Licensed under the GNU GPL, version 2, or any later version published by the
# Free Software Foundation

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "underlay",  call => \&getsetup);
	hook(type => "checkconfig", id => "underlay", call => \&checkconfig);
}

sub getsetup () {
	return
		plugin => {
			safe => 0,
			rebuild => undef,
		},
		add_underlays => {
			type => "string",
			default => [],
			description => "extra underlay directories to add",
			advanced => 1,
			safe => 0,
			rebuild => 1,
		},
}

sub checkconfig () {
	return unless exists $config{add_underlays};

	foreach my $dir (@{$config{add_underlays}}) {
		add_underlay($dir);
	}
}

1;
