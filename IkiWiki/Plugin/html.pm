#!/usr/bin/perl
# Raw html as a wiki page type.
package IkiWiki::Plugin::html;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	IkiWiki::hook(type => "htmlize", id => "html", call => sub { shift });
	IkiWiki::hook(type => "htmlize", id => "htm", call => sub { shift });

	# ikiwiki defaults to skipping .html files as a security measure;
	# make it process them so this plugin can take effect
	$IkiWiki::config{wiki_file_prune_regexp} =~ s/\|\\\.x\?html\?\$//;
} # }}}

1
