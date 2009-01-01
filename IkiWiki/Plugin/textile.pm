#!/usr/bin/perl
# By mazirian; GPL license
# Textile markup

package IkiWiki::Plugin::textile;

use warnings;
use strict;
use IkiWiki 3.00;
use Encode;

sub import {
	hook(type => "getsetup", id => "textile", call => \&getsetup);
	hook(type => "htmlize", id => "txtl", call => \&htmlize);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1, # format plugin
		},
}

sub htmlize (@) {
	my %params=@_;
	my $content = decode_utf8(encode_utf8($params{content}));

	eval q{use Text::Textile};
	return $content if $@;
	return Text::Textile::textile($content);
}

1
