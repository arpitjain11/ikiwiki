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
	IkiWiki::hook(type => "format", id => "tidy", call => \&format);
} # }}}

sub format ($) { #{{{
	open2(*IN, *OUT, 'tidy -quiet -asxhtml -indent -utf8 --show-warnings no') or return shift;
	# open2 doesn't respect "use open ':utf8'"
	binmode (IN, ':utf8'); 
	binmode (OUT, ':utf8'); 
	
	print OUT shift;
	close OUT;

	local $/ = undef;
	return <IN>;
} # }}}

1
