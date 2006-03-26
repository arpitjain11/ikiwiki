#!/usr/bin/perl
# Standard ikiwiki setup module.
# Parameters to import should be all the standard ikiwiki config stuff,
# plus hashes for cgiwrapper and svnwrapper, which specify any differing
# config stuff for them and cause the wrappers to be made.

use warnings;
use strict;
use IkiWiki::Wrapper;
use IkiWiki::Render;

package IkiWiki::Setup::Standard;

sub import {
	IkiWiki::setup_standard(@_);
}
	
package IkiWiki;

sub setup_standard {
	my %setup=%{$_[1]};

	if (! $config{refresh}) {
		debug("generating wrappers..");
		my %startconfig=(%config);
		foreach my $wrapper (@{$setup{wrappers}}) {
			%config=(%startconfig, verbose => 0, %setup, %{$wrapper});
			checkconfig();
			gen_wrapper();
		}
		%config=(%startconfig);
	}
	foreach my $c (keys %setup) {
		$config{$c}=possibly_foolish_untaint($setup{$c})
			if defined $setup{$c} && ! ref $setup{$c};
	}
	if (! $config{refresh}) {
		$config{rebuild}=1;
		debug("rebuilding wiki..");
	}
	else {
		debug("refreshing wiki..");
	}

	checkconfig();
	lockwiki();
	loadindex();
	refresh();

	debug("done");
	saveindex();
}

1
