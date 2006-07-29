#!/usr/bin/perl
# Ikiwiki tag plugin.
package IkiWiki::Plugin::tag;

use warnings;
use strict;
use IkiWiki;

my %tags;

sub import { #{{{
	IkiWiki::hook(type => "getopt", id => "tag",
		call => \&getopt);
	IkiWiki::hook(type => "preprocess", id => "tag",
		call => \&preprocess);
	IkiWiki::hook(type => "pagetemplate", id => "tag",
		call => \&pagetemplate);
} # }}}

sub getopt () { #{{{
	eval q{use Getopt::Long};
	Getopt::Long::Configure('pass_through');
	GetOptions("tagbase=s" => \$IkiWiki::config{tagbase});
} #}}}

sub tagpage ($) { #{{{
	my $tag=shift;
			
	if (exists $IkiWiki::config{tagbase} &&
	    defined $IkiWiki::config{tagbase}) {
		$tag=$IkiWiki::config{tagbase}."/".$tag;
	}

	return $tag;
} #}}}

sub preprocess (@) { #{{{
	if (! @_) {
		return "";
	}
	my %params=@_;
	my $page = $params{page};
	delete $params{page};
	delete $params{destpage};

	$tags{$page} = [];
	foreach my $tag (keys %params) {
		push @{$tags{$page}}, $tag;
		# hidden WikiLink
		push @{$IkiWiki::links{$page}}, tagpage($tag);
	}
		
	return "";
} # }}}

sub pagetemplate (@) { #{{{
	my %params=@_;
	my $page=$params{page};
	my $destpage=$params{destpage};
	my $template=$params{template};

	$template->param(tags => [
		map { 
			link => IkiWiki::htmllink($page, $destpage, tagpage($_))
		}, @{$tags{$page}}
	]) if exists $tags{$page} && @{$tags{$page}} && $template->query(name => "tags");

	if ($template->query(name => "items")) {
		# It's an rss template. Modify each item in the feed,
		# adding any categories based on the page for that item.
		foreach my $item (@{$template->param("items")}) {
			my $p=$item->{page};
			if (exists $tags{$p} && @{$tags{$p}}) {
				$item->{categories}=[];
				foreach my $tag (@{$tags{$p}}) {
					push @{$item->{categories}}, {
						category => $tag,
					};
				}
			}
		}
	}
} # }}}

1
