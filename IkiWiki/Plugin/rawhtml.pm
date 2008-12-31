#!/usr/bin/perl
# Copy html files raw.
package IkiWiki::Plugin::rawhtml;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "rawhtml", call => \&getsetup);
	$config{wiki_file_prune_regexps} = [ grep { !m/\\\.x\?html\?\$/ } @{$config{wiki_file_prune_regexps}} ];
}

sub getsetup () {
	return 
		plugin => {
			safe => 1,
			rebuild => 1, # changes file types
		},
}

1
