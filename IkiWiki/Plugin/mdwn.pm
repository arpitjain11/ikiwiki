#!/usr/bin/perl
# Markdown markup language
package IkiWiki::Plugin::mdwn;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	IkiWiki::hook(type => "htmlize", id => "mdwn", call => \&htmlize);
} # }}}

my $markdown_loaded=0;
sub htmlize (@) { #{{{
	my %params=@_;
	my $content = $params{content};

	if (! $markdown_loaded) {
		# Note: This hack to make markdown run as a proper perl
		# module. A proper perl module is available in Debian
		# for markdown, but not upstream yet.
		no warnings 'once';
		$blosxom::version="is a proper perl module too much to ask?";
		use warnings 'all';

		eval q{use Markdown};
		if ($@) {
			do "/usr/bin/markdown" ||
				IkiWiki::error("failed to load Markdown.pm perl module ($@) or /usr/bin/markdown ($!)");
		}
		$markdown_loaded=1;
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
