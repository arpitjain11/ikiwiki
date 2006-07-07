#!/usr/bin/perl
# WikiText markup
package IkiWiki::Plugin::wikitext;

use warnings;
use strict;
use Text::WikiFormat;

sub import { #{{{
	IkiWiki::hook(type => "filter", id => "wiki", call => \&filter);
	IkiWiki::hook(type => "htmlize", id => "wiki", call => \&htmlize);
} # }}}

sub filter (@) { #{{{
	my %params=@_;

	# Make CamelCase links work by promoting them to fullfledged
	# WikiLinks. This regexp is based on the one in Text::WikiFormat.
	$params{content}=~s#(?<![["/>=])\b((?:[A-Z][a-z0-9]\w*){2,})#[[$1]]#g;

	return $params{content};
} #}}}

sub htmlize ($) { #{{{
	my $content = shift;

	return Text::WikiFormat::format($content, undef, { implicit_links => 0 });
} # }}}

1
