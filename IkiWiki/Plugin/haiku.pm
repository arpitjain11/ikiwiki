#!/usr/bin/perl
# haiku generator plugin
package IkiWiki::Plugin::haiku;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	IkiWiki::hook(type => "preprocess", id => "haiku",
		call => \&preprocess);
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;

	my $haiku;
	eval q{use Coy};
	if ($@) {
		my @canned=(
			"The lack of a Coy:
			 No darting, subtle haiku.
			 Instead, canned tuna.
			",
			"apt-get install Coy
			 no, wait, that's not quite it
			 instead: libcoy-perl
			",
			"Coyly I'll do it,
			 no code, count Five-Seven-Five
			 to make a haiku.
			",
		);
			 		 
		$haiku=$canned[rand @canned];
	}
	else {
		# Coy is rather strange, so the best way to get a haiku
		# out of it is to die..
		eval {die exists $params{hint} ? $params{hint} : $params{page}};
		$haiku=$@;

		# trim off other text
		$haiku=~s/\s+-----\n//s;
		$haiku=~s/\s+-----.*//s;
	}
		
	$haiku=~s/^\s+//mg;
	$haiku=~s/\n/<br>\n/mg;
	
	return $haiku
} # }}}

1
