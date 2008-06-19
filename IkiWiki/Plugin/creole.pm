#!/usr/bin/perl
# WikiCreole markup
# based on the WikiText plugin.
package IkiWiki::Plugin::creole;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "htmlize", id => "creole", call => \&htmlize);
} # }}}

sub htmlize (@) { #{{{
	my %params=@_;
	my $content = $params{content};

	eval q{use Text::WikiCreole};
	return $content if $@;
	return Text::WikiCreole::creole_parse($content);
} # }}}

1
