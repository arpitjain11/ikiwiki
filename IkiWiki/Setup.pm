#!/usr/bin/perl

use warnings;
use strict;

package IkiWiki;

sub setup () { # {{{
	my $setup=possibly_foolish_untaint($config{setup});
	delete $config{setup};
	open (IN, $setup) || error("read $setup: $!\n");
	local $/=undef;
	my $code=<IN>;
	($code)=$code=~/(.*)/s;
	close IN;

	eval $code;
	error($@) if $@;
	exit;
} #}}}

1
