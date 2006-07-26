#!/usr/bin/perl
# WikiText markup
package IkiWiki::Plugin::wikitext;

use warnings;
use strict;
use Text::WikiFormat;

sub import { #{{{
	IkiWiki::hook(type => "htmlize", id => "wiki", call => \&htmlize);
} # }}}

sub htmlize ($) { #{{{
	my $content = shift;

	return Text::WikiFormat::format($content, undef, { implicit_links => 0 });
} # }}}

1
