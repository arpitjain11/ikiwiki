#!/usr/bin/perl
package IkiWiki::Plugin::googlecalendar;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "preprocess", id => "googlecalendar",
		call => \&preprocess);
	hook(type => "format", id => "googlecalendar",
		call => \&format);
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;

	# Parse the html, looking for the url to embed for the calendar.
	# Avoid XSS attacks..
	my ($url)=$params{html}=~m#iframe\s+src="http://www\.google\.com/calendar/embed\?([^"<>]+)"#;
	if (! defined $url || ! length $url) {
		error gettext("failed to find url in html")
	}
	my ($height)=$params{html}=~m#height="(\d+)"#;
	my ($width)=$params{html}=~m#width="(\d+)"#;

	return "<div class=\"googlecalendar\" src=\"$url\" height=\"$height\" width=\"$width\"></div>";
} # }}}

sub format (@) { #{{{
        my %params=@_;

	$params{content}=~s/<div class=\"googlecalendar" src="([^"]+)" height="([^"]+)" width="([^"]+)"><\/div>/gencal($1,$2,$3)/eg;

        return $params{content};
} # }}}

sub gencal ($$$) { #{{{
	my $url=shift;
	my $height=shift;
	my $width=shift;
	return qq{<iframe src="http://www.google.com/calendar/embed?$url" style=" border-width:0 " width="$width" frameborder="0" height="$height"></iframe>};
} #}}}

1
