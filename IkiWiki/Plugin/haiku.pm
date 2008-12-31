#!/usr/bin/perl
# haiku generator plugin
package IkiWiki::Plugin::haiku;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "haiku", call => \&getsetup);
	hook(type => "preprocess", id => "haiku", call => \&preprocess);
}

sub getsetup {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess (@) {
	my %params=@_;

	my $haiku;
	eval q{use Coy};
	if ($@ || ! Coy->can("Coy::with_haiku")) {
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
		$haiku=Coy::with_haiku($params{hint} ? $params{hint} : $params{page});
		
		# trim off other text
		$haiku=~s/\s+-----\n//s;
		$haiku=~s/\s+-----.*//s;
	}
		
	$haiku=~s/^\s+//mg;
	$haiku=~s/\n/<br \/>\n/mg;
	
	return "\n\n<blockquote><p>$haiku</p></blockquote>\n\n";
}

1
