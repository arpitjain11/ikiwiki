#!/usr/bin/perl
package IkiWiki::Plugin::conditional;

use warnings;
use strict;
use IkiWiki 3.00;
use UNIVERSAL;

sub import {
	hook(type => "getsetup", id => "conditional", call => \&getsetup);
	hook(type => "preprocess", id => "if", call => \&preprocess_if);
}

sub getsetup {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess_if (@) {
	my %params=@_;

	foreach my $param (qw{test then}) {
		if (! exists $params{$param}) {
			error sprintf(gettext('%s parameter is required'), $param);
		}
	}

	my $result=0;
	if ((exists $params{all} && lc $params{all} eq "no") ||
		# An optimisation to avoid needless looping over every page
		# and adding of dependencies for simple uses of some of the
		# tests.
		$params{test} =~ /^([\s\!()]*((enabled|sourcepage|destpage|included)\([^)]*\)|(and|or))[\s\!()]*)+$/) {
		add_depends($params{page}, "($params{test}) and $params{page}");
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
		IkiWiki::filter($params{page}, $params{destpage}, $ret));
}

package IkiWiki::PageSpec;

sub match_enabled ($$;@) {
	shift;
	my $plugin=shift;
	
	# test if the plugin is enabled
	if (UNIVERSAL::can("IkiWiki::Plugin::".$plugin, "import")) {
		return IkiWiki::SuccessReason->new("$plugin is enabled");
	}
	else {
		return IkiWiki::FailReason->new("$plugin is not enabled");
	}
}

sub match_sourcepage ($$;@) {
	shift;
	my $glob=shift;
	my %params=@_;
	
	$glob=derel($glob, $params{location});

	return IkiWiki::FailReason->new("cannot match sourcepage") unless exists $params{sourcepage};
	if (match_glob($params{sourcepage}, $glob, @_)) {
		return IkiWiki::SuccessReason->new("sourcepage matches $glob");
	}
	else {
		return IkiWiki::FailReason->new("sourcepage does not match $glob");
	}
}

sub match_destpage ($$;@) {
	shift;
	my $glob=shift;
	my %params=@_;
	
	$glob=derel($glob, $params{location});

	return IkiWiki::FailReason->new("cannot match destpage") unless exists $params{destpage};
	if (match_glob($params{destpage}, $glob, @_)) {
		return IkiWiki::SuccessReason->new("destpage matches $glob");
	}
	else {
		return IkiWiki::FailReason->new("destpage does not match $glob");
	}
}

sub match_included ($$;@) {
	shift;
	shift;
	my %params=@_;

	return IkiWiki::FailReason->new("cannot match included") unless exists $params{sourcepage} && exists $params{destpage};
	if ($params{sourcepage} ne $params{destpage}) {
		return IkiWiki::SuccessReason->new("page $params{sourcepage} is included");
	}
	else {
		return IkiWiki::FailReason->new("page $params{sourcepage} is not included");
	}
}

1
