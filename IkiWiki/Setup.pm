#!/usr/bin/perl

use warnings;
use strict;
use IkiWiki;
use open qw{:utf8 :std};

package IkiWiki;

sub setup () { # {{{
	my $setup=possibly_foolish_untaint($config{setup});
	delete $config{setup};
	#translators: The first parameter is a filename, and the second
	#translators: is a (probably not translated) error message.
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
