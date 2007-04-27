#!/usr/bin/perl
package IkiWiki::Plugin::conditional;

use warnings;
use strict;
use IkiWiki 2.00;
use UNIVERSAL;

sub import { #{{{
	hook(type => "preprocess", id => "if", call => \&preprocess_if);
} # }}}

sub preprocess_if (@) { #{{{
	my %params=@_;

	if (! exists $params{test} || ! exists $params{then}) {
		return "[[if ".gettext('"test" and "then" parameters are required')."]]";
	}

	my $result=0;
	# An optimisation to avoid needless looping over every page
	# and adding of dependencies for simple uses of some of the
	# tests.
	if ($params{test} =~ /^(enabled|sourcepage|destpage)\((.*)\)$/) {
		$result=pagespec_match($params{page}, $params{test},
				location => $params{page},
				sourcepage => $params{page},
				destpage => $params{destpage});
	}
	else {
		add_depends($params{page}, $params{test});

		foreach my $page (keys %pagesources) {
			if (pagespec_match($page, $params{test}, 
					location => $params{page},
					sourcepage => $params{page},
					destpage => $params{destpage})) {
				$result=1;
				last;
			}
		}
	}

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

sub match_enabled ($$;@) { #{{{
	shift;
	my $plugin=shift;
	
	# test if the plugin is enabled
	return UNIVERSAL::can("IkiWiki::Plugin::".$plugin, "import");
} #}}}

sub match_sourcepage ($$;@) { #{{{
	shift;
	my $glob=shift;
	my %params=@_;

	return unless exists $params{sourcepage};
	return match_glob($params{sourcepage}, $glob, @_);
} #}}}

sub match_destpage ($$;@) { #{{{
	shift;
	my $glob=shift;
	my %params=@_;
	
	return unless exists $params{destpage};
	return match_glob($params{destpage}, $glob, @_);
} #}}}

sub match_included ($$;$) { #{{{
	shift;
	shift;
	my %params=@_;

	return unless exists $params{sourcepage} && exists $params{destpage};
	return $params{sourcepage} ne $params{destpage};
} #}}}

1
