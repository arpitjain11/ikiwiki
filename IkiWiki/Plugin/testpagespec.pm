#!/usr/bin/perl
package IkiWiki::Plugin::testpagespec;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "preprocess", id => "testpagespec", call => \&preprocess);
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;
	
	add_depends($params{page}, $params{pagespec});
	
	my $ret=pagespec_match($params{match}, $params{pagespec}, 
			location => $params{page});
	if ($ret) {
		return "match: $ret";
	}
	else {
		return "no match: $ret";
	}
} # }}}

1
