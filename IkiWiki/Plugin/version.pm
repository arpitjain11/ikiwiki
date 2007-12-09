#!/usr/bin/perl
# Ikiwiki version plugin.
package IkiWiki::Plugin::version;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "needsbuild", id => "version", call => \&needsbuild);
	hook(type => "preprocess", id => "version", call => \&preprocess);
} # }}}

sub needsbuild (@) { #{{{
	my $needsbuild=shift;
	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{version}{shown} &&
		    $pagestate{$page}{version}{shown} ne $IkiWiki::version) {
			push @$needsbuild, $pagesources{$page};
		}
	}
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;
	$pagestate{$params{destpage}}{version}{shown}=$IkiWiki::version;
} # }}}

1
