#!/usr/bin/perl
# CamelCase links
package IkiWiki::Plugin::camelcase;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "filter", id => "camelcase", call => \&filter);
} # }}}

sub filter (@) { #{{{
	my %params=@_;

	# Make CamelCase links work by promoting them to fullfledged
	# WikiLinks. This regexp is based on the one in Text::WikiFormat.
	$params{content}=~s{
		(?<![^A-Za-z0-9\s])	# try to avoid expanding non-links
					# with a zero width negative
					# lookbehind for characters that
					# suggest it's not a link
		\b			# word boundry
		(
			(?:
				[A-Z]		# Uppercase start
				[a-z0-9]	# followed by lowercase
				\w*		# and rest of word
			)
			{2,}			# repeated twice
		)
	}{[[$1]]}gx;

	return $params{content};
} #}}}

1
