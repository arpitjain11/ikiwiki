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
			    absdepth => $i,
			    distance => ($pagedepth - $i),
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

sub forget_oldest ($@) { #{{{
	my $offset=shift;
	my @pedigree=@_;
	my @ret;
	my $parent;
	unless ($offset ge scalar(@pedigree)) {
		for (my $i=0; $i < $offset; $i++) {
			shift @pedigree;
		}
		while (@pedigree) {
			# Doing so does not modify the original @pedigree, we've
			# got our own copy of its "content" (i.e. a pile of
			# references to hashes)...
			$parent=shift @pedigree;
			# ... but we have no copy of the referenced hashes, so we
			# actually are modifying them in-place, which
			# means the second (and following) calls to
			# this function overwrite the previous one's
			# reldepth values => known bug if PEDIGREE_BUT_ROOT and
			# PEDIGREE_BUT_TWO_OLDEST are used in the same template
			$parent->{reldepth}=($parent->{absdepth} - $offset);
			push @ret, $parent;
		}
	}
	return @ret;
} #}}}

sub pagetemplate (@) { #{{{
	my %params=@_;
        my $page=$params{page};
        my $template=$params{template};

	my @pedigree=pedigree($page)
	  if ($template->query(name => "pedigree")
	      or $template->query(name => "pedigree_but_root")
	      or $template->query(name => "pedigree_but_two_oldest")
	     );

	$template->param(pedigree => \@pedigree)
	  if ($template->query(name => "pedigree"));
	$template->param(pedigree_but_root => [forget_oldest(1, @pedigree)])
	  if ($template->query(name => "pedigree_but_root"));
	$template->param(pedigree_but_two_oldest => [forget_oldest(2, @pedigree)])
	  if ($template->query(name => "pedigree_but_two_oldest"));

} # }}}

1
