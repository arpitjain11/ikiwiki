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

	debug("generating wrappers..");
	my %startconfig=(%config);
	foreach my $wrapper (@{$setup{wrappers}}) {
		%config=(%startconfig, verbose => 0, %setup, %{$wrapper});
		checkoptions();
		gen_wrapper();
	}
	%config=(%startconfig);
	
	debug("rebuilding wiki..");
	foreach my $c (keys %setup) {
		$config{$c}=possibly_foolish_untaint($setup{$c})
			if defined $setup{$c} && ! ref $setup{$c};
	}
	$config{rebuild}=1;
	checkoptions();
	refresh();

	debug("done");
	saveindex();
}

1
