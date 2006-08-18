#!/usr/bin/perl
#
# Produce a hyerarchical map of links.
#
# By Alessandro Dotti Contra <alessandro@hyboria.org>
#
# Revision: 0.1
package IkiWiki::Plugin::map;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	IkiWiki::hook(type => "preprocess", id => "map",
		call => \&preprocess);
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;
	$params{pages}="*" unless defined $params{pages};
	
	# Needs to update whenever a page is added or removed, so
	# register a dependency.
	IkiWiki::add_depends($params{page}, $params{pages});
	
	# Get all the items to map.
	my @mapitems = ();
	foreach my $page (keys %IkiWiki::links) {
		if (IkiWiki::pagespec_match($page, $params{pages})) {
			push @mapitems, $page;
		}
	}

	# Create the map.
	my $indent=0;
	my $map = "<div class='map'>\n";
	foreach my $item (sort @mapitems) {
		my $depth = ($item =~ tr/\//\//) + 1;
		next if exists $params{maxdepth} && $depth > $params{maxdepth};
		while ($depth < $indent) {
			$indent--;
			$map.="</ul>\n";
		}
		while ($depth > $indent) {
			$indent++;
			$map.="<ul>\n";
		}
		$map .= "<li>"
		        .IkiWiki::htmllink($params{page}, $params{destpage}, $item)
			."</li>\n";
	}
	while ($indent > 0) {
		$indent--;
		$map.="</ul>\n";
	}
	$map .= "</div>\n";
	return $map;
} # }}}

1
