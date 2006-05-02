#!/usr/bin/perl
# Provides a list of broken links.
package IkiWiki::Plugin::brokenlinks;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	IkiWiki::register_plugin("preprocess", "brokenlinks", \&preprocess);
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;
	$params{pages}="*" unless defined $params{pages};
	
	# Needs to update whenever a page is added or removed, so
	# register a dependency.
	IkiWiki::add_depends($params{page}, $params{pages});
	
	my @broken;
	foreach my $page (%IkiWiki::links) {
		if (IkiWiki::globlist_match($page, $params{pages})) {
			foreach my $link (@{$IkiWiki::links{$page}}) {
				next if $link =~ /.*\/discussion/i;
				my $bestlink=IkiWiki::bestlink($page, $link);
				next if length $bestlink;
				push @broken,
					IkiWiki::htmllink($page, $link, 1).
					" in ".
					IkiWiki::htmllink($params{page}, $page, 1);
			}
		}
	}
	
	return "There are no broken links!" unless @broken;
	return "<ul>\n".join("\n", map { "<li>$_</li>" } sort @broken)."</ul>\n";
} # }}}

1
