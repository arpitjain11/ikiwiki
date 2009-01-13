#!/usr/bin/perl
package IkiWiki::Plugin::repolist;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "repolist",  call => \&getsetup);
	hook(type => "checkconfig", id => "repolist", call => \&checkconfig);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
		repositories => {
			type => "string",
			example => ["svn://svn.example.org/wiki/trunk"],
			description => "URIs of repositories containing the wiki's source",
			safe => 1,
			rebuild => undef,
		},
}

my $relvcs;

sub checkconfig () {
	if (defined $config{rcs} && $config{repositories}) {
		$relvcs=join("\n", map {
			s/"//g; # avoid quotes just in case
			qq{<link rel="vcs-$config{rcs}" href="$_" title="wiki $config{rcs} repository" />}
		} @{$config{repositories}});
		
		hook(type => "pagetemplate", id => "repolist", call => \&pagetemplate);
	}
}

sub pagetemplate (@) {
	my %params=@_;
	my $page=$params{page};
	my $template=$params{template};
	
        if (defined $relvcs && $template->query(name => "relvcs")) {
		$template->param(relvcs => $relvcs);
	}
}

1
