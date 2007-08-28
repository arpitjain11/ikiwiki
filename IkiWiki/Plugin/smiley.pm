#!/usr/bin/perl
package IkiWiki::Plugin::smiley;

use warnings;
use strict;
use IkiWiki 2.00;

my %smileys;
my $smiley_regexp;

sub import { #{{{
	add_underlay("smiley");
	hook(type => "filter", id => "smiley", call => \&filter);
} # }}}

sub build_regexp () { #{{{
	my $list=readfile(srcfile("smileys.mdwn"));
	while ($list =~ m/^\s*\*\s+\\([^\s]+)\s+\[\[([^]]+)\]\]/mg) {
		$smileys{$1}=$2;
	}
	
	if (! %smileys) {
		debug(gettext("failed to parse any smileys"));
		$smiley_regexp='';
		return;
	}
	
	# sort and reverse so that substrings come after longer strings
	# that contain them, in most cases.
	$smiley_regexp='('.join('|', map { quotemeta }
		reverse sort keys %smileys).')';
	#debug($smiley_regexp);
} #}}}

sub filter (@) { #{{{
	my %params=@_;
	
	build_regexp() unless defined $smiley_regexp;
	$params{content} =~ s{(?:^|(?<=\s))(\\?)$smiley_regexp(?:(?=\s)|$)}{
		$1 ? $2 : htmllink($params{page}, $params{destpage}, $smileys{$2}, linktext => $2)
	}egs if length $smiley_regexp;

	return $params{content};
} # }}}

1
