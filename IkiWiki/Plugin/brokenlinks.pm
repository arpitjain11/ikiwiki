#!/usr/bin/perl
# Provides a list of broken links.
package IkiWiki::Plugin::brokenlinks;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	hook(type => "preprocess", id => "brokenlinks", call => \&preprocess);
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;
	$params{pages}="*" unless defined $params{pages};
	
	# Needs to update whenever a page is added or removed, so
	# register a dependency.
	add_depends($params{page}, $params{pages});
	
	my @broken;
	foreach my $page (keys %links) {
		if (pagespec_match($page, $params{pages}, $params{page})) {
			my $discussion=gettext("discussion");
			foreach my $link (@{$links{$page}}) {
				next if $link =~ /.*\/\Q$discussion\E/i && $config{discussion};
				my $bestlink=bestlink($page, $link);
				next if length $bestlink;
				push @broken,
					htmllink($page, $params{destpage}, $link, 1).
					" from ".
					htmllink($params{page}, $params{destpage}, $page, 1);
			}
		}
	}
	
	return gettext("There are no broken links!") unless @broken;
	my %seen;
	return "<ul>\n".join("\n", map { "<li>$_</li>" } grep { ! $seen{$_}++ } sort @broken)."</ul>\n";
} # }}}

1
