#!/usr/bin/perl
# Ikiwiki tag plugin.
package IkiWiki::Plugin::tag;

use warnings;
use strict;
use IkiWiki;

my %tag;

sub import { #{{{
	IkiWiki::hook(type => "preprocess", id => "tag", call => \&preprocess);
} # }}}

sub preprocess (@) { #{{{
	if (! @_) {
		return "";
	}
	my %params=@_;
	my $page = $params{page};
	delete $params{page};

	foreach my $tag (keys %params) {
		# hidden WikiLink
		push @{$IkiWiki::links{$page}}, $tag;
	}
		
	return "";
} # }}}

1
