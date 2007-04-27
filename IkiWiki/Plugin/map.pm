#!/usr/bin/perl
#
# Produce a hierarchical map of links.
#
# by Alessandro Dotti Contra <alessandro@hyboria.org>
#
# Revision: 0.2
package IkiWiki::Plugin::map;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "preprocess", id => "map", call => \&preprocess);
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;
	$params{pages}="*" unless defined $params{pages};
	
	# Needs to update whenever a page is added or removed, so
	# register a dependency.
	add_depends($params{page}, $params{pages});
	
	# Get all the items to map.
	my @mapitems = ();
	foreach my $page (keys %links) {
		if (pagespec_match($page, $params{pages}, location => $params{page})) {
			push @mapitems, $page;
		}
	}

	# Create the map.
	my $indent=0;
	my $openli=0;
	my $map = "<div class='map'>\n";
	$map .= "<ul>\n";
	foreach my $item (sort @mapitems) {
		my $depth = ($item =~ tr/\//\//);
		while ($depth < $indent) {
			$indent--;
			$map.="</li></ul>\n";
		}
		while ($depth > $indent) {
			$indent++;
			$map.="<ul>\n";
			$openli=0;
		}
		$map .= "</li>\n" if $openli;
		$map .= "<li>"
			.htmllink($params{page}, $params{destpage}, $item)
			."\n";
		$openli=1;
	}
	while ($indent > 0) {
		$indent--;
		$map.="</li></ul>\n";
	}
	$map .= "</li></ul>\n";
	$map .= "</div>\n";
	return $map;
} # }}}

1
