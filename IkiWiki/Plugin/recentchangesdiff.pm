#!/usr/bin/perl
package IkiWiki::Plugin::recentchangesdiff;

use warnings;
use strict;
use IkiWiki 2.00;

my $maxlines=200;

sub import { #{{{
	hook(type => "getsetup", id => "recentchangesdiff",
		call => \&getsetup);
	hook(type => "pagetemplate", id => "recentchangesdiff",
		call => \&pagetemplate);
} #}}}

sub getsetup () { #{{{
	return 
		plugin => {
			safe => 1,
			rebuild => 1,
		},
} #}}}

sub pagetemplate (@) { #{{{
	my %params=@_;
	my $template=$params{template};
	if ($config{rcs} && exists $params{rev} && length $params{rev} &&
	    $template->query(name => "diff")) {
		my @lines=IkiWiki::rcs_diff($params{rev});
		if (@lines) {
			my $diff;
			if (@lines > $maxlines) {
				# only include so many lines of diff
				$diff=join("", @lines[0..($maxlines-1)])."\n".
					gettext("(Diff truncated)");
			}
			else {
				$diff=join("", @lines);
			}
			# escape links and preprocessor stuff
			$diff =~ s/(?<!\\)\[\[/\\\[\[/g;
			$template->param(diff => $diff);
		}
	}
} #}}}

1
