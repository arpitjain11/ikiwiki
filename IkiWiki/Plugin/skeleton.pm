#!/usr/bin/perl
# Ikiwiki skeleton plugin. Replace "skeleton" with the name of your plugin
# in the lines below, and flesh out the methods to make it do something.
package IkiWiki::Plugin::skeleton;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	IkiWiki::register_plugin("preprocess", "skeleton", \&preprocess);
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;

	return "skeleton plugin result";
} # }}}

1
