#!/usr/bin/perl
# Ikiwiki skeleton plugin. Replace "skeleton" with the name of your plugin
# in the lines below, remove hooks you don't use, and flesh out the code to
# make it do something.
package IkiWiki::Plugin::skeleton;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "getopt", id => "skeleton",  call => \&getopt);
	hook(type => "checkconfig", id => "skeleton", call => \&checkconfig);
	hook(type => "needsbuild", id => "skeleton", call => \&needsbuild);
	hook(type => "preprocess", id => "skeleton", call => \&preprocess);
	hook(type => "filter", id => "skeleton", call => \&filter);
	hook(type => "linkify", id => "skeleton", call => \&linkify);
	hook(type => "scan", id => "skeleton", call => \&scan);
	hook(type => "htmlize", id => "skeleton", call => \&htmlize);
	hook(type => "sanitize", id => "skeleton", call => \&sanitize);
	hook(type => "format", id => "skeleton", call => \&format);
	hook(type => "pagetemplate", id => "skeleton", call => \&pagetemplate);
	hook(type => "templatefile", id => "skeleton", call => \&templatefile);
	hook(type => "delete", id => "skeleton", call => \&delete);
	hook(type => "change", id => "skeleton", call => \&change);
	hook(type => "cgi", id => "skeleton", call => \&cgi);
	hook(type => "auth", id => "skeleton", call => \&auth);
	hook(type => "sessioncgi", id => "skeleton", call => \&sessioncgi);
	hook(type => "canedit", id => "skeleton", call => \&canedit);
	hook(type => "editcontent", id => "skeleton", call => \&editcontent);
	hook(type => "formbuilder_setup", id => "skeleton", call => \&formbuilder_setup);
	hook(type => "formbuilder", id => "skeleton", call => \&formbuilder);
	hook(type => "savestate", id => "skeleton", call => \&savestate);
} # }}}

sub getopt () { #{{{
	debug("skeleton plugin getopt");
} #}}}

sub checkconfig () { #{{{
	debug("skeleton plugin checkconfig");
} #}}}

sub needsbuild () { #{{{
	debug("skeleton plugin needsbuild");
} #}}}

sub preprocess (@) { #{{{
	my %params=@_;

	return "skeleton plugin result";
} # }}}

sub filter (@) { #{{{
	my %params=@_;
	
	debug("skeleton plugin running as filter");

	return $params{content};
} # }}}

sub linkify (@) { #{{{
	my %params=@_;
	
	debug("skeleton plugin running as linkify");

	return $params{content};
} # }}}

sub scan (@) { #{{{a
	my %params=@_;

	debug("skeleton plugin running as scan");
} # }}}

sub htmlize (@) { #{{{
	my %params=@_;

	debug("skeleton plugin running as htmlize");

	return $params{content};
} # }}}

sub sanitize (@) { #{{{
	my %params=@_;
	
	debug("skeleton plugin running as a sanitizer");

	return $params{content};
} # }}}

sub format (@) { #{{{
	my %params=@_;
	
	debug("skeleton plugin running as a formatter");

	return $params{content};
} # }}}

sub pagetemplate (@) { #{{{
	my %params=@_;
	my $page=$params{page};
	my $template=$params{template};
	
	debug("skeleton plugin running as a pagetemplate hook");
} # }}}

sub templatefile (@) { #{{{
	my %params=@_;
	my $page=$params{page};
	
	debug("skeleton plugin running as a templatefile hook");
} # }}}

sub delete (@) { #{{{
	my @files=@_;

	debug("skeleton plugin told that files were deleted: @files");
} #}}}

sub change (@) { #{{{
	my @files=@_;

	debug("skeleton plugin told that changed files were rendered: @files");
} #}}}

sub cgi ($) { #{{{
	my $cgi=shift;

	debug("skeleton plugin running in cgi");
} #}}}

sub auth ($$) { #{{{
	my $cgi=shift;
	my $session=shift;

	debug("skeleton plugin running in auth");
} #}}}

sub sessionncgi ($$) { #{{{
	my $cgi=shift;
	my $session=shift;

	debug("skeleton plugin running in sessioncgi");
} #}}}

sub canedit ($$$) { #{{{
	my $page=shift;
	my $cgi=shift;
	my $session=shift;

	debug("skeleton plugin running in canedit");
} #}}}

sub editcontent ($$$) { #{{{
	my %params=@_;

	debug("skeleton plugin running in editcontent");

	return $params{content};
} #}}}

sub formbuilder_setup (@) { #{{{
	my %params=@_;
	
	debug("skeleton plugin running in formbuilder_setup");
} # }}}

sub formbuilder (@) { #{{{
	my %params=@_;
	
	debug("skeleton plugin running in formbuilder");
} # }}}

sub savestate () { #{{{
	debug("skeleton plugin running in savestate");
} #}}}

1