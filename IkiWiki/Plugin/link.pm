#!/usr/bin/perl
package IkiWiki::Plugin::link;

use warnings;
use strict;
use IkiWiki 2.00;

my $link_regexp;

sub import { #{{{
	hook(type => "checkconfig", id => "link", call => \&checkconfig);
	hook(type => "linkify", id => "link", call => \&linkify);
	hook(type => "scan", id => "link", call => \&scan);
} # }}}

sub checkconfig () { #{{{
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
} #}}}

sub linkify (@) { #{{{
	my %params=@_;
	my $page=$params{page};
	my $destpage=$params{destpage};

	$params{content} =~ s{(\\?)$link_regexp}{
		defined $2
			? ( $1 
				? "[[$2|$3".($4 ? "#$4" : "")."]]" 
				: htmllink($page, $destpage, IkiWiki::linkpage($3),
					anchor => $4, linktext => IkiWiki::pagetitle($2)))
			: ( $1 
				? "[[$3".($4 ? "#$4" : "")."]]"
				: htmllink($page, $destpage, IkiWiki::linkpage($3),
					anchor => $4))
	}eg;
	
	return $params{content};
} #}}}

sub scan (@) { #{{{
	my %params=@_;
	my $page=$params{page};
	my $content=$params{content};

	while ($content =~ /(?<!\\)$link_regexp/g) {
		push @{$links{$page}}, IkiWiki::linkpage($2);
	}
} # }}}

1
