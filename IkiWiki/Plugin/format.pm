#!/usr/bin/perl
package IkiWiki::Plugin::format;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "preprocess", id => "format", call => \&preprocess);
}

sub preprocess (@) {
	my $format=$_[0];
	shift; shift;
	my $text=$_[0];
	shift; shift;
	my %params=@_;

	if (! defined $format || ! defined $text) {
		error(gettext("must specify format and text"));
	}
	elsif (! exists $IkiWiki::hooks{htmlize}{$format}) {
		error(sprintf(gettext("unsupported page format %s"), $format));
	}

	return IkiWiki::htmlize($params{page}, $params{destpage}, $format,
		IkiWiki::preprocess($params{page}, $params{destpage}, $text));
}

1
