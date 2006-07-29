#!/usr/bin/perl
#
# Produce page statistics in various forms.
#
# Currently supported:
#   cloud: produces statistics in the form of a del.icio.us-style tag cloud
#          (default)
#   table: produces a table with the number of backlinks for each page
#
# By Enrico Zini.
package IkiWiki::Plugin::pagestats;

use warnings;
use strict;
use IkiWiki;

# Names of the HTML classes to use for the tag cloud
our @classes = ('smallestPC', 'smallPC', 'normalPC', 'bigPC', 'biggestPC' );

sub import { #{{{
	IkiWiki::hook(type => "preprocess", id => "pagestats",
		call => \&preprocess);
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;
	$params{pages}="*" unless defined $params{pages};
	my $style = ($params{style} or 'cloud');
	
	# Needs to update whenever a page is added or removed, so
	# register a dependency.
	IkiWiki::add_depends($params{page}, $params{pages});
	
	my %counts;
	my $max = 0;
	foreach my $page (%IkiWiki::links) {
		if (IkiWiki::globlist_match($page, $params{pages})) {
			my @bl = IkiWiki::backlinks($page);
			$counts{$page} = scalar(@bl);
			$max = $counts{$page} if $counts{$page} > $max;
		}
	}

	if ($style eq 'table') {
		return "<table class='pageStats'>\n".
			join("\n", map {
				"<tr><td>".
				IkiWiki::htmllink($params{page}, $params{destpage}, $_, 1).
				"</td><td>".$counts{$_}."</td></tr>"
			}
			sort { $counts{$b} <=> $counts{$a} } keys %counts).
			"\n</table>\n" ;
	} else {
		# In case of misspelling, default to a page cloud

		my $res = "<div class='pagecloud'>\n";
		foreach my $page (sort keys %counts) {
			my $class = $classes[$counts{$page} * scalar(@classes) / ($max + 1)];
			$res .= "<span class=\"$class\">".
			        IkiWiki::htmllink($params{page}, $params{destpage}, $page).
			        "</span>\n";
		}
		$res .= "</div>\n";

		return $res;
	}
} # }}}

1
