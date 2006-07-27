#!/usr/bin/perl
# Provides a list of pages no other page links to.
package IkiWiki::Plugin::orphans;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	IkiWiki::hook(type => "preprocess", id => "orphans",
		call => \&preprocess);
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;
	$params{pages}="*" unless defined $params{pages};
	
	# Needs to update whenever a page is added or removed, so
	# register a dependency.
	IkiWiki::add_depends($params{page}, $params{pages});
	
	my %linkedto;
	foreach my $p (keys %IkiWiki::links) {
		map { $linkedto{IkiWiki::bestlink($p, $_)}=1 if length $_ }
			@{$IkiWiki::links{$p}};
	}
	
	my @orphans;
	foreach my $page (keys %IkiWiki::renderedfiles) {
		next if $linkedto{$page};
		next unless IkiWiki::globlist_match($page, $params{pages});
		# If the page has a link to some other page, it's
		# indirectly linked to a page via that page's backlinks.
		next if grep { 
			length $_ &&
			($_ !~ /\/Discussion$/i || ! $IkiWiki::config{discussion}) &&
			IkiWiki::bestlink($page, $_) !~ /^($page|)$/ 
		} @{$IkiWiki::links{$page}};
		push @orphans, $page;
	}
	
	return "All pages are linked to by other pages." unless @orphans;
	return "<ul>\n".join("\n", map { "<li>".IkiWiki::htmllink($params{page}, $params{destpage}, $_, 1)."</li>" } sort @orphans)."</ul>\n";
} # }}}

1
