#!/usr/bin/perl
# Standard ikiwiki setup module.
# Parameters to import should be all the standard ikiwiki config stuff,
# plus an array of wrappers to set up.

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
		delete $config{wrappers};
	}
	foreach my $c (keys %setup) {
		if (defined $setup{$c}) {
			if (! ref $setup{$c}) {
				$config{$c}=possibly_foolish_untaint($setup{$c});
			}
			elsif (ref $setup{$c} eq 'ARRAY') {
				$config{$c}=[map { possibly_foolish_untaint($_) } @{$setup{$c}}]
			}
		}
		else {
			$config{$c}=undef;
		}
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
