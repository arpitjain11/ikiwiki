#!/usr/bin/perl
# Markdown markup language
package IkiWiki::Plugin::mdwn;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "htmlize", id => "mdwn", call => \&htmlize);
} # }}}

my $markdown_sub;
sub htmlize (@) { #{{{
	my %params=@_;
	my $content = $params{content};

	if (! defined $markdown_sub) {
		# Markdown is forked and splintered upstream and can be
		# available in a variety of incompatible forms. Support
		# them all.
		no warnings 'once';
		$blosxom::version="is a proper perl module too much to ask?";
		use warnings 'all';

		eval q{use Markdown};
		if (! $@) {
			$markdown_sub=\&Markdown::Markdown;
		}
		else {
			eval q{use Text::Markdown};
			if (! $@) {
				$markdown_sub=\&Text::Markdown::Markdown;
			}
			else {
				do "/usr/bin/markdown" ||
					error(sprintf(gettext("failed to load Markdown.pm perl module (%s) or /usr/bin/markdown (%s)"), $@, $!));
				$markdown_sub=\&Markdown::Markdown;
			}
		}
		require Encode;
	}
	
	my $oneline = $content !~ /\n/;

	# Workaround for perl bug (#376329)
	$content=Encode::encode_utf8($content);
	eval {$content=&$markdown_sub($content)};
	if ($@) {
		eval {$content=&$markdown_sub($content)};
		print STDERR $@ if $@;
	}
	$content=Encode::decode_utf8($content);

	if ($oneline) {
		# hack to get rid of enclosing junk added by markdown
		$content=~s!^<p>!!;
		$content=~s!</p>$!!;
		chomp $content;
	}

	return $content;
} # }}}

1
