#!/usr/bin/perl
# WikiText markup
package IkiWiki::Plugin::wikitext;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	hook(type => "htmlize", id => "wiki", call => \&htmlize);
} # }}}

sub htmlize (@) { #{{{
	my %params=@_;
	my $content = $params{content};

	eval q{use Text::WikiFormat};
	return $content if $@;
	return Text::WikiFormat::format($content, undef, { implicit_links => 0 });
} # }}}

1
