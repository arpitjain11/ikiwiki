#!/usr/bin/perl
package IkiWiki::Plugin::smiley;

use warnings;
use strict;
use IkiWiki 2.00;

my %smileys;
my $smiley_regexp;

sub import { #{{{
	add_underlay("smiley");
	hook(type => "getsetup", id => "smiley", call => \&getsetup);
	hook(type => "sanitize", id => "smiley", call => \&sanitize);
} # }}}

sub getsetup () { #{{{
	return
		plugin => {
			safe => 1,
			# force a rebuild because turning it off
			# removes the smileys, which would break links
			rebuild => 1,
		},
} #}}}

sub build_regexp () { #{{{
	my $list=readfile(srcfile("smileys.mdwn"));
	while ($list =~ m/^\s*\*\s+\\\\([^\s]+)\s+\[\[([^]]+)\]\]/mg) {
		my $smiley=$1;
		my $file=$2;

		$smileys{$smiley}=$file;

		# Add a version with < and > escaped, since they probably
		# will be (by markdown) by the time the sanitize hook runs.
		$smiley=~s/</&lt;/g;
		$smiley=~s/>/&gt;/g;
		$smileys{$smiley}=$file;
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

sub sanitize (@) { #{{{
	my %params=@_;

	build_regexp() unless defined $smiley_regexp;
	
	$_=$params{content};
	return $_ unless length $smiley_regexp;
			
MATCH:	while (m{(?:^|(?<=\s|>))(\\?)$smiley_regexp(?:(?=\s|<)|$)}g) {
		my $escape=$1;
		my $smiley=$2;
		my $epos=$-[1];
		my $spos=$-[2];
		
		# Smilies are not allowed inside <pre> or <code>.
		# For each tag in turn, match forward to find the next <tag>
		# or </tag> after the smiley.
		my $pos=pos;
		foreach my $tag ("pre", "code") {
			if (m/<(\/)?\s*$tag\s*>/isg && defined $1) {
				# </tag> found first, so the smiley is
				# inside the tag, so do not expand it.
				next MATCH;
			}
			# Reset pos back to where it was before this test.
			pos=$pos;
		}
	
		if ($escape) {
			# Remove escape.
			substr($_, $epos, 1)="";
			pos=$epos+1;
		}
		else {
			# Replace the smiley with its expanded value.
			substr($_, $spos, length($smiley))=
				htmllink($params{page}, $params{destpage},
				         $smileys{$smiley}, linktext => $smiley);
			pos=$epos+1;
		}

		# Breaks out at end, otherwise it will scan through again,
		# replacing de-escaped ones.
		#last unless defined pos;
	}

	return $_;
} # }}}

1
