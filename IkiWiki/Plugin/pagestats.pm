#!/usr/bin/perl
#
# Produce page statistics in various forms.
#
# Currently supported:
#   cloud: produces statistics in the form of a del.icio.us-style tag cloud
#          (default)
#   table: produces a table with the number of backlinks for each page
#
# by Enrico Zini
package IkiWiki::Plugin::pagestats;

use warnings;
use strict;
use IkiWiki 3.00;

# Names of the HTML classes to use for the tag cloud
our @classes = ('smallestPC', 'smallPC', 'normalPC', 'bigPC', 'biggestPC' );

sub import {
	hook(type => "getsetup", id => "pagestats", call => \&getsetup);
	hook(type => "preprocess", id => "pagestats", call => \&preprocess);
}

sub getsetup () {
	return 
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess (@) {
	my %params=@_;
	$params{pages}="*" unless defined $params{pages};
	my $style = ($params{style} or 'cloud');
	
	# Needs to update whenever a page is added or removed, so
	# register a dependency.
	add_depends($params{page}, $params{pages});
	
	my %counts;
	my $max = 0;
	foreach my $page (keys %links) {
		if (pagespec_match($page, $params{pages}, location => $params{page})) {
			use IkiWiki::Render;
			$counts{$page} = scalar(IkiWiki::backlinks($page));
			$max = $counts{$page} if $counts{$page} > $max;
		}
	}

	if ($style eq 'table') {
		return "<table class='pageStats'>\n".
			join("\n", map {
				"<tr><td>".
				htmllink($params{page}, $params{destpage}, $_, noimageinline => 1).
				"</td><td>".$counts{$_}."</td></tr>"
			}
			sort { $counts{$b} <=> $counts{$a} } keys %counts).
			"\n</table>\n" ;
	}
	else {
		# In case of misspelling, default to a page cloud

		my $res = "<div class='pagecloud'>\n";
		foreach my $page (sort keys %counts) {
			my $class = $classes[$counts{$page} * scalar(@classes) / ($max + 1)];
			$res .= "<span class=\"$class\">".
			        htmllink($params{page}, $params{destpage}, $page).
			        "</span>\n";
		}
		$res .= "</div>\n";

		return $res;
	}
}

1
