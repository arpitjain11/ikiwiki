#!/usr/bin/perl
# Provides [[pagecount ]] to count the number of pages.
package IkiWiki::Plugin::pagecount;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	IkiWiki::hook(type => "preprocess", id => "pagecount", 
		call => \&preprocess);
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;
	$params{pages}="*" unless defined $params{pages};
	
	# Needs to update count whenever a page is added or removed, so
	# register a dependency.
	IkiWiki::add_depends($params{page}, $params{pages});
	
	my @pages=keys %IkiWiki::pagesources;
	return $#pages+1 if $params{pages} eq "*"; # optimisation
	my $count=0;
	foreach my $page (@pages) {
		$count++ if IkiWiki::pagespec_match($page, $params{pages});
	}
	return $count;
} # }}}

1
