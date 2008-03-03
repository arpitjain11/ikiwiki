#!/usr/bin/perl
package IkiWiki::Plugin::recentchangesdiff;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "pagetemplate", id => "recentchangesdiff",
		call => \&pagetemplate);
} #}}}

sub pagetemplate (@) { #{{{
	my %params=@_;
	my $template=$params{template};
	if ($config{rcs} && exists $params{rev} && length $params{rev} &&
	    $template->query(name => "diff")) {
		my $diff=IkiWiki::rcs_diff($params{rev});
		if (defined $diff && length $diff) {
			# escape links and preprocessor stuff
			$diff =~ s/(?<!\\)\[\[/\\\[\[/g;
			$template->param(diff => $diff);
		}
	}
} #}}}

1
