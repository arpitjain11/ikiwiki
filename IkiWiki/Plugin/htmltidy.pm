#!/usr/bin/perl
# HTML Tidy plugin
# requires 'tidy' binary, found in Debian or http://tidy.sf.net/
# mostly a proof-of-concept on how to use external filters.
# It is particularly useful when the html plugin is used.
#
# by Faidon Liambotis
package IkiWiki::Plugin::htmltidy;

use warnings;
use strict;
use IkiWiki;
use IPC::Open2;

sub import { #{{{
	IkiWiki::hook(type => "sanitize", id => "tidy", call => \&sanitize);
} # }}}

sub sanitize ($) { #{{{
	open2(*IN, *OUT, 'tidy -quiet -xml -indent -utf8') or return shift;
	# open2 doesn't respect "use open ':utf8'"
	binmode (IN, ':utf8'); 
	binmode (OUT, ':utf8'); 
	
	print OUT shift;
	close OUT;

	local $/ = undef;
	return <IN>;
} # }}}

1
