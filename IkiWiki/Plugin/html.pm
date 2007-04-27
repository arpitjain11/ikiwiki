#!/usr/bin/perl
# Raw html as a wiki page type.
package IkiWiki::Plugin::html;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "htmlize", id => "html", call => \&htmlize);
	hook(type => "htmlize", id => "htm", call => \&htmlize);

	# ikiwiki defaults to skipping .html files as a security measure;
	# make it process them so this plugin can take effect
	$config{wiki_file_prune_regexps} = [ grep { !m/\\\.x\?html\?\$/ } @{$config{wiki_file_prune_regexps}} ];
} # }}}

sub htmlize (@) { #{{{
	my %params=@_;
	return $params{content};
} #}}}

1
