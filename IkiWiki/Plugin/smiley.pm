#!/usr/bin/perl
package IkiWiki::Plugin::smiley;

use warnings;
use strict;
use IkiWiki;

my %smileys;
my $smiley_regexp;

sub import { #{{{
	hook(type => "checkconfig", id => "smiley", call => \&setup);
} # }}}

sub setup () { #{{{
	my $list=readfile(srcfile("smileys.mdwn"));
	while ($list =~ m/^\s*\*\s+\\([^\s]+)\s+\[\[([^]]+)\]\]/mg) {
		$smileys{$1}=$2;
	}
	
	if (! %smileys) {
		debug(gettext("failed to parse any smileys, disabling plugin"));
		return;
	}
	
	hook(type => "filter", id => "smiley", call => \&filter);
	# sort and reverse so that substrings come after longer strings
	# that contain them, in most cases.
	$smiley_regexp='('.join('|', map { quotemeta }
		reverse sort keys %smileys).')';
	#debug($smiley_regexp);
} #}}}

sub filter (@) { #{{{
	my %params=@_;
	
	$params{content} =~ s{(?<=\s)(\\?)$smiley_regexp(?=\s)}{
		$1 ? $2 : htmllink($params{page}, $params{page}, $smileys{$2}, 0, 0, $2)
	}egs;
	
	return $params{content};
} # }}}

1
