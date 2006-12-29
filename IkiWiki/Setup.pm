#!/usr/bin/perl

use warnings;
use strict;
use IkiWiki;
use open qw{:utf8 :std};

package IkiWiki;

sub setup () { # {{{
	my $setup=possibly_foolish_untaint($config{setup});
	delete $config{setup};
	open (IN, $setup) || error(sprintf(gettext("cannot read %s: %s"), $setup, $!));
	my $code;
	{
		local $/=undef;
		$code=<IN>;
	}
	($code)=$code=~/(.*)/s;
	close IN;

	eval $code;
	error($@) if $@;

	exit;
} #}}}

1
