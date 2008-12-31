#!/usr/bin/perl
package IkiWiki::Plugin::link;

use warnings;
use strict;
use IkiWiki 3.00;

my $link_regexp;

sub import {
	hook(type => "getsetup", id => "link", call => \&getsetup);
	hook(type => "checkconfig", id => "link", call => \&checkconfig);
	hook(type => "linkify", id => "link", call => \&linkify);
	hook(type => "scan", id => "link", call => \&scan);
	hook(type => "renamepage", id => "link", call => \&renamepage);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
}

sub checkconfig () {
	if ($config{prefix_directives}) {
		$link_regexp = qr{
			\[\[(?=[^!])            # beginning of link
			(?:
				([^\]\|]+)      # 1: link text
				\|              # followed by '|'
			)?                      # optional
			
			([^\n\r\]#]+)           # 2: page to link to
			(?:
				\#              # '#', beginning of anchor
				([^\s\]]+)      # 3: anchor text
			)?                      # optional
			
			\]\]                    # end of link
		}x;
	}
	else {
		$link_regexp = qr{
			\[\[                    # beginning of link
			(?:
				([^\]\|\n\s]+)  # 1: link text
				\|              # followed by '|'
			)?                      # optional

			([^\s\]#]+)             # 2: page to link to
			(?:
				\#              # '#', beginning of anchor
				([^\s\]]+)      # 3: anchor text
			)?                      # optional

			\]\]                    # end of link
		}x,
	}
}

sub linkify (@) {
	my %params=@_;
	my $page=$params{page};
	my $destpage=$params{destpage};

	$params{content} =~ s{(\\?)$link_regexp}{
		defined $2
			? ( $1 
				? "[[$2|$3".($4 ? "#$4" : "")."]]" 
				: htmllink($page, $destpage, linkpage($3),
					anchor => $4, linktext => pagetitle($2)))
			: ( $1 
				? "[[$3".($4 ? "#$4" : "")."]]"
				: htmllink($page, $destpage, linkpage($3),
					anchor => $4))
	}eg;
	
	return $params{content};
}

sub scan (@) {
	my %params=@_;
	my $page=$params{page};
	my $content=$params{content};

	while ($content =~ /(?<!\\)$link_regexp/g) {
		push @{$links{$page}}, linkpage($2);
	}
}

sub renamepage (@) {
	my %params=@_;
	my $page=$params{page};
	my $old=$params{oldpage};
	my $new=$params{newpage};

	$params{content} =~ s{(?<!\\)$link_regexp}{
		my $linktext=$2;
		my $link=$linktext;
		if (bestlink($page, linkpage($linktext)) eq $old) {
			$link=pagetitle($new, 1);
			$link=~s/ /_/g;
			if ($linktext =~ m/.*\/*?[A-Z]/) {
				# preserve leading cap of last component
				my @bits=split("/", $link);
				$link=join("/", @bits[0..$#bits-1], ucfirst($bits[$#bits]));
			}
			if (index($linktext, "/") == 0) {
				# absolute link
				$link="/$link";
			}
		}
		defined $1
			? ( "[[$1|$link".($3 ? "#$3" : "")."]]" )
			: ( "[[$link".   ($3 ? "#$3" : "")."]]" )
	}eg;

	return $params{content};
}

1
