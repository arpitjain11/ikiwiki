#!/usr/bin/perl
# Ikiwiki listdirectives plugin.
package IkiWiki::Plugin::listdirectives;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	add_underlay("directives");
	hook(type => "getsetup", id => "listdirectives", call => \&getsetup);
	hook(type => "checkconfig", id => "listdirectives", call => \&checkconfig);
	hook(type => "needsbuild", id => "listdirectives", call => \&needsbuild);
	hook(type => "preprocess", id => "listdirectives", call => \&preprocess);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
		directive_description_dir => {
			type => "string",
			description => "directory in srcdir that contains directive descriptions",
			example => "ikiwiki/directive",
			safe => 1,
			rebuild => 1,
		},
}

my @fulllist;
my @shortlist;
my $pluginstring;

sub checkconfig () {
	if (! defined $config{directive_description_dir}) {
		$config{directive_description_dir} = "ikiwiki/directive";
	}
	else {
		$config{directive_description_dir} =~ s/\/+$//;
	}
}

sub needsbuild (@) {
	my $needsbuild=shift;

	@fulllist = sort keys %{$IkiWiki::hooks{preprocess}};
	@shortlist = grep { ! $IkiWiki::hooks{preprocess}{$_}{shortcut} } @fulllist;
	$pluginstring = join(' ', @shortlist) . " : " . join(' ', @fulllist);

	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{listdirectives}{shown}) {
			if ($pagestate{$page}{listdirectives}{shown} ne $pluginstring) {
				push @$needsbuild, $pagesources{$page};
			}
			if (exists $pagesources{$page} &&
			    grep { $_ eq $pagesources{$page} } @$needsbuild) {
				# remove state, will be re-added if
				# the [[!listdirectives]] is still there during the
				# rebuild
				delete $pagestate{$page}{listdirectives}{shown};
			}
		}
	}
}

sub preprocess (@) {
	my %params=@_;
	
	$pagestate{$params{destpage}}{listdirectives}{shown}=$pluginstring;
	
	my @pluginlist;
	
	if (defined $params{generated}) {
		@pluginlist = @fulllist;
	}
	else {
		@pluginlist = @shortlist;
	}
	
	my $result = '<ul class="listdirectives">';
	
	foreach my $plugin (@pluginlist) {
		$result .= '<li class="listdirectives">';
		my $link=linkpage($config{directive_description_dir}."/".$plugin);
		add_depends($params{page}, $link);
		$result .= htmllink($params{page}, $params{destpage}, $link);
		$result .= '</li>';
	}
	
	$result .= "</ul>";

	return $result;
}

1
