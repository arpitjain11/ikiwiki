#!/usr/bin/perl
# CamelCase links
package IkiWiki::Plugin::camelcase;

use warnings;
use strict;
use IkiWiki 3.00;

# This regexp is based on the one in Text::WikiFormat.
my $link_regexp=qr{
	(?<![^A-Za-z0-9\s])	# try to avoid expanding non-links with a
				# zero width negative lookbehind for
				# characters that suggest it's not a link
	\b			# word boundry
	(
		(?:
			[A-Z]		# Uppercase start
			[a-z0-9]	# followed by lowercase
			\w*		# and rest of word
		)
		{2,}			# repeated twice
	)
}x;

sub import {
	hook(type => "getsetup", id => "camelcase", call => \&getsetup);
	hook(type => "linkify", id => "camelcase", call => \&linkify);
	hook(type => "scan", id => "camelcase", call => \&scan);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
		camelcase_ignore => {
			type => "string",
			example => [],
			description => "list of words to not turn into links",
			safe => 1,
			rebuild => undef, # might change links
		},
}

sub linkify (@) {
	my %params=@_;
	my $page=$params{page};
	my $destpage=$params{destpage};

	$params{content}=~s{$link_regexp}{
		ignored($1) ? $1 : htmllink($page, $destpage, linkpage($1))
	}eg;

	return $params{content};
}

sub scan (@) {
        my %params=@_;
        my $page=$params{page};
        my $content=$params{content};

	while ($content =~ /$link_regexp/g) {
		push @{$links{$page}}, linkpage($1) unless ignored($1)
	}
}

sub ignored ($) {
	my $word=lc shift;
	grep { $word eq lc $_ } @{$config{'camelcase_ignore'}}
}

1
