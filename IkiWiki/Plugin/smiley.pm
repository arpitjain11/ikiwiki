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
	
	$_=$params{content};
	return $_ unless length $smiley_regexp;
	
MATCH:	while (m{(?:^|(?<=\s))(\\?)$smiley_regexp(?:(?=\s)|$)}g) {
		# Smilies are not allowed inside <pre> or <code>.
		# For each tag in turn, match forward to find <tag> or
		# </tag>. If it's </tag>, then the smiley is inside the
		# tag, and is not expanded. If it's <tag>, the smiley is
		# outside the block.
		my $pos=pos;
		foreach my $tag ("pre", "code") {
			if (m/.*?<(\/)?\s*$tag\s*>/isg) {
				if (defined $1) {
					# Inside tag, so do nothing.
					# (Smiley hunting will continue after
					# the tag.)
					next MATCH;
				}
				else {
					# Reset pos back to where it was before
					# this test.
					pos=$pos;
				}
			}
		}

		if ($1) {
			# Remove escape.
			substr($_, $-[1], 1)="";
		}
		else {
			# Replace the smiley with its expanded value.
			substr($_, $-[2], length($2))=
				htmllink($params{page}, $params{destpage}, $smileys{$2}, linktext => $2);
		}
	}

	return $_;
} # }}}

1
