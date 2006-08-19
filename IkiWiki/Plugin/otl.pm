#!/usr/bin/perl
# outline markup
package IkiWiki::Plugin::otl;

use warnings;
use strict;
use IkiWiki;
use IPC::Open2;

sub import { #{{{
	IkiWiki::hook(type => "filter", id => "otl", call => \&filter);
	IkiWiki::hook(type => "htmlize", id => "otl", call => \&htmlize);

} # }}}

sub filter (@) { #{{{
	my %params=@_;
        
	# Munge up check boxes to look a little bit better. This is a hack.
	my $checked=IkiWiki::htmllink($params{page}, $params{page},
		"smileys/star_on.png", 0);
	my $unchecked=IkiWiki::htmllink($params{page}, $params{page},
		"smileys/star_off.png", 0);
	$params{content}=~s/^(\s+)\[X\]\s/${1}$checked /mg;
	$params{content}=~s/^(\s+)\[_\]\s/${1}$unchecked /mg;
        
	return $params{content};
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
	$ret=~s/<div class="Footer">.*//s;
	return $ret;
} # }}}

1
