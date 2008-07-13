#!/usr/bin/perl
# -*- cperl-indent-level: 8; -*-
# Ikiwiki pedigree plugin.
package IkiWiki::Plugin::pedigree;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "pagetemplate", id => "pedigree", call => \&pagetemplate);
} # }}}

sub pedigree ($) { #{{{
	my $page=shift;

	my @ret;
	my $path="";
	my $title=$config{wikiname};
	my $i=0;

	my @pagepath=(split("/", $page));
	my $pagedepth=@pagepath;
	foreach my $dir (@pagepath) {
		next if $dir eq 'index';
		push @ret, {
			    url => urlto($path, $page),
			    page => $title,
			    level => $i,
			    is_root => ($i eq 0),
			    is_second_ancestor => ($i eq 1),
			    is_grand_mother => ($i eq ($pagedepth - 2)),
			    is_mother => ($i eq ($pagedepth - 1)),
			   };
		$path.="/".$dir;
		$title=IkiWiki::pagetitle($dir);
		$i++;
	}
	return @ret;
} #}}}

sub pagetemplate (@) { #{{{
	my %params=@_;
        my $page=$params{page};
        my $template=$params{template};

	if ($template->query(name => "pedigree")) {
		$template->param(pedigree => [pedigree($page)]);
	}

} # }}}

1
