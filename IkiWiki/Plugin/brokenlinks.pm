#!/usr/bin/perl
# Provides a list of broken links.
package IkiWiki::Plugin::brokenlinks;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "brokenlinks", call => \&getsetup);
	hook(type => "preprocess", id => "brokenlinks", call => \&preprocess);
}

sub getsetup {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess (@) {
	my %params=@_;
	$params{pages}="*" unless defined $params{pages};
	
	# Needs to update whenever a page is added or removed, so
	# register a dependency.
	add_depends($params{page}, $params{pages});
	
	my %broken;
	foreach my $page (keys %links) {
		if (pagespec_match($page, $params{pages}, location => $params{page})) {
			my $discussion=gettext("discussion");
			my %seen;
			foreach my $link (@{$links{$page}}) {
				next if $seen{$link};
				$seen{$link}=1;
				next if $link =~ /.*\/\Q$discussion\E/i && $config{discussion};
				my $bestlink=bestlink($page, $link);
				next if length $bestlink;
				push @{$broken{$link}}, $page;
			}
		}
	}

	my @broken;
	foreach my $link (keys %broken) {
		my $page=$broken{$link}->[0];
		push @broken, sprintf(gettext("%s from %s"),
			htmllink($page, $params{destpage}, $link, noimageinline => 1),
			join(", ", map {
				htmllink($params{page}, $params{destpage}, $_, 	noimageinline => 1)
			} @{$broken{$link}}));
	}
	
	return gettext("There are no broken links!") unless %broken;
	return "<ul>\n"
		.join("\n",
			map {
				"<li>$_</li>"
			}
			sort @broken)
		."</ul>\n";
}

1
