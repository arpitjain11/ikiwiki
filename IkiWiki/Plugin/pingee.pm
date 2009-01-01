#!/usr/bin/perl
package IkiWiki::Plugin::pingee;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "pingee", call => \&getsetup);
	hook(type => "cgi", id => "pingee", call => \&cgi);
}

sub getsetup () {
	return 
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub cgi ($) {
	my $cgi=shift;

	if (defined $cgi->param('do') && $cgi->param("do") eq "ping") {
		$|=1;
		print "Content-Type: text/plain\n\n";
		$config{cgi}=0;
		$config{verbose}=1;
		$config{syslog}=0;
		print gettext("Ping received.")."\n\n";

		IkiWiki::lockwiki();
		IkiWiki::loadindex();
		require IkiWiki::Render;
		IkiWiki::rcs_update();
		IkiWiki::refresh();
		IkiWiki::saveindex();
		exit 0;
	}
}

1
