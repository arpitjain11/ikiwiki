#!/usr/bin/perl
package IkiWiki::Plugin::lockedit;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "lockedit", call => \&getsetup);
	hook(type => "canedit", id => "lockedit", call => \&canedit);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
		},
		locked_pages => {
			type => "pagespec",
			example => "!*/Discussion",
			description => "PageSpec controlling which pages are locked",
			link => "ikiwiki/PageSpec",
			safe => 1,
			rebuild => 0,
		},
}

sub canedit ($$) {
	my $page=shift;
	my $cgi=shift;
	my $session=shift;

	my $user=$session->param("name");
	return undef if defined $user && IkiWiki::is_admin($user);

	if (defined $config{locked_pages} && length $config{locked_pages} &&
	    pagespec_match($page, $config{locked_pages},
		    user => $session->param("name"),
		    ip => $ENV{REMOTE_ADDR},
	    )) {
		if (! defined $user ||
		    ! IkiWiki::userinfo_get($session->param("name"), "regdate")) {
			return sub { IkiWiki::needsignin($cgi, $session) };
		}
		else {
			return sprintf(gettext("%s is locked and cannot be edited"),
				htmllink("", "", $page, noimageinline => 1));
			
		}
	}

	return undef;
}

1
