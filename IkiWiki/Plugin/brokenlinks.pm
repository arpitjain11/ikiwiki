#!/usr/bin/perl
# Provides a list of broken links.
package IkiWiki::Plugin::brokenlinks;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	IkiWiki::hook(type => "preprocess", id => "brokenlinks",
		call => \&preprocess);
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;
	$params{pages}="*" unless defined $params{pages};
	
	# Needs to update whenever a page is added or removed, so
	# register a dependency.
	IkiWiki::add_depends($params{page}, $params{pages});
	
	my @broken;
	foreach my $page (keys %IkiWiki::links) {
		if (IkiWiki::pagespec_match($page, $params{pages})) {
			foreach my $link (@{$IkiWiki::links{$page}}) {
				next if $link =~ /.*\/discussion/i && $IkiWiki::config{discussion};
				my $bestlink=IkiWiki::bestlink($page, $link);
				next if length $bestlink;
				push @broken,
					IkiWiki::htmllink($page, $params{destpage}, $link, 1).
					" in ".
					IkiWiki::htmllink($params{page}, $params{destpage}, $page, 1);
			}
		}
	}
	
	return "There are no broken links!" unless @broken;
	my %seen;
	return "<ul>\n".join("\n", map { "<li>$_</li>" } grep { ! $seen{$_}++ } sort @broken)."</ul>\n";
} # }}}

1
