#!/usr/bin/perl
# WikiText markup
package IkiWiki::Plugin::wikitext;

use warnings;
use strict;
use IkiWiki;
use Text::WikiFormat;

sub import { #{{{
	hook(type => "htmlize", id => "wiki", call => \&htmlize);
} # }}}

sub htmlize (@) { #{{{
	my %params=@_;
	my $content = $params{content};

	return Text::WikiFormat::format($content, undef, { implicit_links => 0 });
} # }}}

1
