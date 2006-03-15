#!/usr/bin/perl
# Standard ikiwiki setup module.
# Parameters to import should be all the standard ikiwiki config stuff,
# plus hashes for cgiwrapper and svnwrapper, which specify any differing
# config stuff for them and cause the wrappers to be made.

package IkiWiki::Setup::Standard;

use warnings;
use strict;

sub import {
	my %setup=%{$_[1]};


	::debug("generating wrappers..");
	foreach my $wrapper (@{$setup{wrapper}}) {
		::gen_wrapper(%::config, %setup, %{$wrapper});
	}

	::debug("rebuilding wiki..");
	foreach my $c (keys %setup) {
		$::config{$c}=::possibly_foolish_untaint($setup{$c})
			if defined $setup{$c} && ! ref $setup{$c};
	}
	$::config{rebuild}=1;
	::refresh();

	::debug("done");
	::saveindex();
}

1
