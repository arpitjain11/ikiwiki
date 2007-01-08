#!/usr/bin/perl
# Copy html files raw.
package IkiWiki::Plugin::rawhtml;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	$config{wiki_file_prune_regexps} = [ grep { !m/\\\.x\?html\?\$/ } @{$config{wiki_file_prune_regexps}} ];
} # }}}

1
