#!/usr/bin/perl
# Markdown markup language
package IkiWiki::Plugin::mdwn;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "mdwn", call => \&getsetup);
	hook(type => "htmlize", id => "mdwn", call => \&htmlize);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1, # format plugin
		},
		multimarkdown => {
			type => "boolean",
			example => 0,
			description => "enable multimarkdown features?",
			safe => 1,
			rebuild => 1,
		},
}

my $markdown_sub;
sub htmlize (@) {
	my %params=@_;
	my $content = $params{content};

	if (! defined $markdown_sub) {
		# Markdown is forked and splintered upstream and can be
		# available in a variety of forms. Support them all.
		no warnings 'once';
		$blosxom::version="is a proper perl module too much to ask?";
		use warnings 'all';

		if (exists $config{multimarkdown} && $config{multimarkdown}) {
			eval q{use Text::MultiMarkdown};
			if ($@) {
				debug(gettext("multimarkdown is enabled, but Text::MultiMarkdown is not installed"));
			}
			$markdown_sub=sub {
				Text::MultiMarkdown::markdown(shift, {use_metadata => 0});
			}
		}
		if (! defined $markdown_sub) {
			eval q{use Text::Markdown};
			if (! $@) {
				if (Text::Markdown->can('markdown')) {
					$markdown_sub=\&Text::Markdown::markdown;
				}
				else {
					$markdown_sub=\&Text::Markdown::Markdown;
				}
			}
			else {
				eval q{use Markdown};
				if (! $@) {
					$markdown_sub=\&Markdown::Markdown;
				}
				else {
					do "/usr/bin/markdown" ||
						error(sprintf(gettext("failed to load Markdown.pm perl module (%s) or /usr/bin/markdown (%s)"), $@, $!));
					$markdown_sub=\&Markdown::Markdown;
				}
			}
		}
		
		require Encode;
	}
	
	# Workaround for perl bug (#376329)
	$content=Encode::encode_utf8($content);
	eval {$content=&$markdown_sub($content)};
	if ($@) {
		eval {$content=&$markdown_sub($content)};
		print STDERR $@ if $@;
	}
	$content=Encode::decode_utf8($content);

	return $content;
}

1
