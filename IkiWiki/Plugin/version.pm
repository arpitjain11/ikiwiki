#!/usr/bin/perl
# Ikiwiki version plugin.
package IkiWiki::Plugin::version;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "version", call => \&getsetup);
	hook(type => "needsbuild", id => "version", call => \&needsbuild);
	hook(type => "preprocess", id => "version", call => \&preprocess);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub needsbuild (@) {
	my $needsbuild=shift;
	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{version}{shown}) {
			if ($pagestate{$page}{version}{shown} ne $IkiWiki::version) {
				push @$needsbuild, $pagesources{$page};
			}
			if (exists $pagesources{$page} &&
			    grep { $_ eq $pagesources{$page} } @$needsbuild) {
				# remove state, will be re-added if
				# the version is still shown during the
				# rebuild
				delete $pagestate{$page}{version}{shown};
			}
		}
	}
}

sub preprocess (@) {
	my %params=@_;
	$pagestate{$params{destpage}}{version}{shown}=$IkiWiki::version;
}

1
