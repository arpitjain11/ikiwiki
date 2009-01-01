#!/usr/bin/perl
package IkiWiki::Plugin::relativedate;

use warnings;
no warnings 'redefine';
use strict;
use IkiWiki 3.00;
use POSIX;
use Encode;

sub import {
	add_underlay("javascript");
	hook(type => "getsetup", id => "relativedate", call => \&getsetup);
	hook(type => "format", id => "relativedate", call => \&format);
	inject(name => "IkiWiki::displaytime", call => \&mydisplaytime);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
}

sub format (@) {
        my %params=@_;

	if (! ($params{content}=~s!^(<body>)!$1.include_javascript($params{page})!em)) {
		# no </body> tag, probably in preview mode
		$params{content}=include_javascript($params{page}, 1).$params{content};
	}
	return $params{content};
}

sub include_javascript ($;$) {
	my $page=shift;
	my $absolute=shift;
	
	return '<script src="'.urlto("ikiwiki.js", $page, $absolute).
		'" type="text/javascript" charset="utf-8"></script>'."\n".
		'<script src="'.urlto("relativedate.js", $page, $absolute).
		'" type="text/javascript" charset="utf-8"></script>';
}

sub mydisplaytime ($;$) {
	my $time=shift;
	my $format=shift;

	# This needs to be in a form that can be parsed by javascript.
	# Being fairly human readable is also nice, as it will be exposed
	# as the title if javascript is not available.
	my $gmtime=decode_utf8(POSIX::strftime("%a, %d %b %Y %H:%M:%S %z",
			localtime($time)));

	return '<span class="relativedate" title="'.$gmtime.'">'.
		IkiWiki::formattime($time, $format).'</span>';
}

1
