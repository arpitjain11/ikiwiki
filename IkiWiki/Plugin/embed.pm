#!/usr/bin/perl
package IkiWiki::Plugin::embed;

use warnings;
use strict;
use IkiWiki 3.00;

my $attribr=qr/[^<>"]+/;

# regexp matching known-safe html
my $safehtml=qr{(
	# google maps
	<\s*iframe\s+width="\d+"\s+height="\d+"\s+frameborder="$attribr"\s+
	scrolling="$attribr"\s+marginheight="\d+"\s+marginwidth="\d+"\s+
	src="http://maps.google.com/\?$attribr"\s*>\s*</iframe>

	|

	# youtube
	<\s*object\s+width="\d+"\s+height="\d+"\s*>\s*
	<\s*param\s+name="movie"\s+value="http://www.youtube.com/v/$attribr"\s*>\s*
	</param>\s*
	<\s*param\s+name="wmode"\s+value="transparent"\s*>\s*</param>\s*
	<embed\s+src="http://www.youtube.com/v/$attribr"\s+
	type="application/x-shockwave-flash"\s+wmode="transparent"\s+
	width="\d+"\s+height="\d+"\s*>\s*</embed>\s*</object>

	|

	# google video
	<\s*embed\s+style="\s*width:\d+px;\s+height:\d+px;\s*"\s+id="$attribr"\s+
	type="application/x-shockwave-flash"\s+
	src="http://video.google.com/googleplayer.swf\?$attribr"\s+
	flashvars=""\s*>\s*</embed>

	|

	# google calendar
	<\s*iframe\s+src="http://www.google.com/calendar/embed\?src=$attribr"\s+
	style="\s*border-width:\d+\s*"\s+width="\d+"\s+frameborder="\d+"\s*
	height="\d+"\s*>\s*</iframe>
)}sx;

my @embedded;

sub import {
	hook(type => "getsetup", id => "embed", call => \&getsetup);
	hook(type => "filter", id => "embed", call => \&filter);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub embed ($) {
	hook(type => "format", id => "embed", call => \&format) unless @embedded;
	push @embedded, shift;
	return "<div class=\"embed$#embedded\"></div>";
}

sub filter (@) {
	my %params=@_;
	$params{content} =~ s/$safehtml/embed($1)/eg;
	return $params{content};
}

sub format (@) {
        my %params=@_;
	$params{content} =~ s/<div class="embed(\d+)"><\/div>/$embedded[$1]/eg;
        return $params{content};
}

1
