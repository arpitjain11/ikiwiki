#!/usr/bin/perl
# outline markup
package IkiWiki::Plugin::otl;

use warnings;
use strict;
use IkiWiki;
use IPC::Open2;

sub import { #{{{
	IkiWiki::hook(type => "htmlize", id => "otl", call => \&htmlize);
} # }}}

sub htmlize ($) { #{{{
	my $tries=10;
	while (1) {
		eval {
			open2(*IN, *OUT, 'otl2html -S /dev/null -T /dev/stdin');
		};
		last unless $@;
		$tries--;
		if ($tries < 1) {
			IkiWiki::debug("failed to run otl2html: $@");
			return shift;
		}
	}
	# open2 doesn't respect "use open ':utf8'"
	binmode (IN, ':utf8'); 
	binmode (OUT, ':utf8'); 
	
	print OUT shift;
	close OUT;

	local $/ = undef;
	my $ret=<IN>;
	$ret=~s/.*<body>//s;
	$ret=~s/<body>.*//s;
	return $ret;
} # }}}

1
