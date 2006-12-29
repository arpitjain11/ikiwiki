#!/usr/bin/perl
# By mazirian; GPL license
# Textile markup

package IkiWiki::Plugin::textile;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	hook(type => "htmlize", id => "txtl", call => \&htmlize);
} # }}}

sub htmlize (@) { #{{{
	my %params=@_;
	my $content = $params{content};

	eval q{use Text::Textile};
	return $content if $@;
	return Text::Textile::textile($content);
} # }}}

1
