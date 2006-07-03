#!/usr/bin/perl
# Markdown markup language
package IkiWiki::Plugin::mdwn;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	IkiWiki::hook(type => "htmlize", id => "mdwn", call => \&htmlize);
} # }}}

sub htmlize ($) { #{{{
	my $content = shift;

	if (! $INC{"/usr/bin/markdown"}) {
		# Note: a proper perl module is available in Debian
		# for markdown, but not upstream yet.
		no warnings 'once';
		$blosxom::version="is a proper perl module too much to ask?";
		use warnings 'all';
		do "/usr/bin/markdown";
		require Encode;
	}
	
	# Workaround for perl bug (#376329)
	$content=Encode::encode_utf8($content);
	$content=Encode::encode_utf8($content);
	$content=Markdown::Markdown($content);
	$content=Encode::decode_utf8($content);
	$content=Encode::decode_utf8($content);

	return $content;
} # }}}

1
