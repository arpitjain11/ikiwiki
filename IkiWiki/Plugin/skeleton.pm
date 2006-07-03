#!/usr/bin/perl
# Ikiwiki skeleton plugin. Replace "skeleton" with the name of your plugin
# in the lines below, remove hooks you don't use, and flesh out the code to
# make it do something.
package IkiWiki::Plugin::skeleton;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	IkiWiki::hook(type => "checkconfig", id => "skeleton", 
		call => \&checkconfig);
	IkiWiki::hook(type => "preprocess", id => "skeleton", 
		call => \&preprocess);
	IkiWiki::hook(type => "filter", id => "skeleton", 
		call => \&filter);
	IkiWiki::hook(type => "htmlize", id => "skeleton",
		call => \&htmlize);
	IkiWiki::hook(type => "sanitize", id => "skeleton", 
		call => \&sanitize);
	IkiWiki::hook(type => "pagetemplate", id => "skeleton", 
		call => \&pagetemplate);
	IkiWiki::hook(type => "delete", id => "skeleton", 
		call => \&delete);
	IkiWiki::hook(type => "change", id => "skeleton", 
		call => \&change);
	IkiWiki::hook(type => "cgi", id => "skeleton", 
		call => \&cgi);
} # }}}

sub checkconfig () { #{{{
	IkiWiki::debug("skeleton plugin checkconfig");
} #}}}

sub preprocess (@) { #{{{
	my %params=@_;

	return "skeleton plugin result";
} # }}}

sub filter (@) { #{{{
	my %params=@_;
	
	IkiWiki::debug("skeleton plugin running as filter");

	return $params{content};
} # }}}

sub htmlize ($) { #{{{
	my $content=shift;

	IkiWiki::debug("skeleton plugin running as htmlize");

	return $content;
} # }}}

sub sanitize ($) { #{{{
	my $content=shift;
	
	IkiWiki::debug("skeleton plugin running as a sanitizer");

	return $content;
} # }}}

sub pagetemplate ($$) { #{{{
	my $page=shift;
	my $template=shift;
	
	IkiWiki::debug("skeleton plugin running as a pagetemplate hook");
} # }}}

sub delete (@) { #{{{
	my @files=@_;

	IkiWiki::debug("skeleton plugin told that files were deleted: @files");
} #}}}

sub change (@) { #{{{
	my @files=@_;

	IkiWiki::debug("skeleton plugin told that changed files were rendered: @files");
} #}}}

sub cgi ($) { #{{{
	my $cgi=shift;

	IkiWiki::debug("skeleton plugin running in cgi");
} #}}}

1
