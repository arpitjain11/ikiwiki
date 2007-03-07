#!/usr/bin/perl
package IkiWiki::Plugin::conditional;

use warnings;
use strict;
use IkiWiki;
use UNIVERSAL;

# Globals used to pass information into the PageSpec functions.
our ($sourcepage, $destpage);

sub import { #{{{
	hook(type => "preprocess", id => "if", call => \&preprocess_if);
} # }}}

sub preprocess_if (@) { #{{{
	my %params=@_;

	if (! exists $params{test} || ! exists $params{then}) {
		return "[[if ".gettext('"test" and "then" parameters are required')."]]";
	}

	my $result=0;
	$sourcepage=$params{page};
	$destpage=$params{destpage};
	# An optimisation to avoid needless looping over every page
	# and adding of dependencies for simple uses of some of the
	# tests.
	if ($params{test} =~ /^(enabled|sourcepage|destpage)\((.*)\)$/) {
		$result=eval "IkiWiki::PageSpec::match_$1(undef, ".
			IkiWiki::safequote($2).")";
	}
	else {
		add_depends($params{page}, $params{test});

		foreach my $page (keys %pagesources) {
			if (pagespec_match($page, $params{test}, $params{page})) {
				$result=1;
				last;
			}
		}
	}
	$sourcepage="";
	$destpage="";

	my $ret;
	if ($result) {
		$ret=$params{then};
	}
	elsif (exists $params{else}) {
		$ret=$params{else};
	}
	else {
		$ret="";
	}
	return IkiWiki::preprocess($params{page}, $params{destpage}, 
		IkiWiki::filter($params{page}, $ret));
} # }}}

package IkiWiki::PageSpec;

sub match_enabled ($$) { #{{{
	shift;
	my $plugin=shift;
	
	# test if the plugin is enabled
	return UNIVERSAL::can("IkiWiki::Plugin::".$plugin, "import");
} #}}}

sub match_sourcepage ($$) { #{{{
	shift;
	my $glob=shift;
	
	return match_glob($IkiWiki::Plugin::conditional::sourcepage, $glob,
		$IkiWiki::Plugin::conditional::sourcepage);
} #}}}

sub match_destpage ($$) { #{{{
	shift;
	my $glob=shift;
	
	return match_glob($IkiWiki::Plugin::conditional::destpage, $glob,
		$IkiWiki::Plugin::conditional::sourcepage);
} #}}}

sub match_included ($$) { #{{{
	return $IkiWiki::Plugin::conditional::sourcepage ne $IkiWiki::Plugin::conditional::destpage;
} #}}}

1
