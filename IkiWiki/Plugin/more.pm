#!/usr/bin/perl
package IkiWiki::Plugin::more;

use warnings;
use strict;
use IkiWiki 3.00;

my $linktext = gettext("more");

sub import {
	hook(type => "getsetup", id => "more", call => \&getsetup);
	hook(type => "preprocess", id => "more", call => \&preprocess);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess (@) {
	my %params=@_;

	$params{linktext} = $linktext unless defined $params{linktext};

	if ($params{page} ne $params{destpage}) {
		return "\n".
			htmllink($params{page}, $params{destpage}, $params{page},
				linktext => $params{linktext},
				anchor => "more");
	}
	else {
		$params{text}=IkiWiki::preprocess($params{page}, $params{destpage},
			IkiWiki::filter($params{page}, $params{destpage}, $params{text}));
		return "<a name=\"more\"></a>\n\n".$params{text};
	}
}

1
