#!/usr/bin/perl
# Ikiwiki skeleton plugin. Replace "skeleton" with the name of your plugin
# in the lines below, and flesh out the code to make it do something.
package IkiWiki::Plugin::skeleton;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	IkiWiki::hook(type => "preprocess", id => "skeleton", 
		call => \&preprocess);
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;

	return "skeleton plugin result";
} # }}}

1
