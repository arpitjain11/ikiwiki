#!/usr/bin/perl
# Sidebar plugin.
# by Tuomo Valkonen <tuomov at iki dot fi>

package IkiWiki::Plugin::sidebar;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	IkiWiki::hook(type => "pagetemplate", id => "sidebar", 
		call => \&pagetemplate);
} # }}}

sub sidebar_content ($) { #{{{
	my $page=shift;
	
	my $sidebar_page=IkiWiki::bestlink($page, "sidebar") || return;
	my $sidebar_file=$IkiWiki::pagesources{$sidebar_page} || return;
	my $sidebar_type=IkiWiki::pagetype($sidebar_file);
	
	if (defined $sidebar_type) {
		# FIXME: This isn't quite right; it won't take into account
		# adding a new sidebar page. So adding such a page
		# currently requires a wiki rebuild.
		IkiWiki::add_depends($page, $sidebar_page);

		my $content=IkiWiki::readfile(IkiWiki::srcfile($sidebar_file));
		return unless length $content;
		return IkiWiki::htmlize($sidebar_type,
		       IkiWiki::linkify($sidebar_page, $page,
		       IkiWiki::preprocess($sidebar_page, $page,
		       IkiWiki::filter($sidebar_page, $content))));
	}

} # }}}

sub pagetemplate (@) { #{{{
	my %params=@_;

	my $page=$params{page};
	my $template=$params{template};
	
	if ($template->query(name => "sidebar")) {
		my $content=sidebar_content($page);
		if (defined $content && length $content) {
		        $template->param(sidebar => $content);
		}
	}
} # }}}

1
