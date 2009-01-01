#!/usr/bin/perl
# .txt as a wiki page type - links WikiLinks and URIs.
#
# Copyright (C) 2008 Gabriel McManus <gmcmanus@gmail.com>
# Licensed under the GNU General Public License, version 2 or later

package IkiWiki::Plugin::txt;

use warnings;
use strict;
use IkiWiki 3.00;
use HTML::Entities;

my $findurl=0;

sub import {
	hook(type => "getsetup", id => "txt", call => \&getsetup);
	hook(type => "filter", id => "txt", call => \&filter);
	hook(type => "htmlize", id => "txt", call => \&htmlize);

	eval q{use URI::Find};
	if (! $@) {
		$findurl=1;
	}
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1, # format plugin
		},
}

# We use filter to convert raw text to HTML
# (htmlize is called after other plugins insert HTML)
sub filter (@) {
	my %params = @_;
	my $content = $params{content};

	if (defined $pagesources{$params{page}} && $pagesources{$params{page}} =~ /\.txt$/) {
		encode_entities($content, "<>&");
		if ($findurl) {
			my $finder = URI::Find->new(sub {
				my ($uri, $orig_uri) = @_;
				return qq|<a href="$uri">$orig_uri</a>|;
			});
			$finder->find(\$content);
		}
		$content = "<pre>" . $content . "</pre>";
	}

	return $content;
}

# We need this to register the .txt file extension
sub htmlize (@) {
	my %params=@_;
	return $params{content};
}

1
