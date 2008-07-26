#!/usr/bin/perl
package IkiWiki::Plugin::cutpaste;

use warnings;
use strict;
use IkiWiki 2.00;
use UNIVERSAL;

my %savedtext;

sub import { #{{{
	hook(type => "preprocess", id => "cut", call => \&preprocess_cut, scan => 1);
	hook(type => "preprocess", id => "copy", call => \&preprocess_copy, scan => 1);
	hook(type => "preprocess", id => "paste", call => \&preprocess_paste);
} # }}}

sub preprocess_cut (@) { #{{{
	my %params=@_;

	foreach my $param (qw{id text}) {
		if (! exists $params{$param}) {
			return "[[cut ".sprintf(gettext('%s parameter is required'), $param)."]]";
		}
	}

	$savedtext{$params{page}} = {} if not exists $savedtext{$params{"page"}};
	$savedtext{$params{page}}->{$params{id}} = $params{text};

	return "" if defined wantarray;
} # }}}

sub preprocess_copy (@) { #{{{
	my %params=@_;

	foreach my $param (qw{id text}) {
		if (! exists $params{$param}) {
			return "[[copy ".sprintf(gettext('%s parameter is required'), $param)."]]";
		}
	}

	$savedtext{$params{page}} = {} if not exists $savedtext{$params{"page"}};
	$savedtext{$params{page}}->{$params{id}} = $params{text};

	return IkiWiki::preprocess($params{page}, $params{destpage}, 
		IkiWiki::filter($params{page}, $params{destpage}, $params{text})) if defined wantarray;
} # }}}

sub preprocess_paste (@) { #{{{
	my %params=@_;

	foreach my $param (qw{id}) {
		if (! exists $params{$param}) {
			return "[[paste ".sprintf(gettext('%s parameter is required'), $param)."]]";
		}
	}

	if (! exists $savedtext{$params{page}}) {
		return "[[paste ".gettext('no text was copied in this page')."]]";
	}
	if (! exists $savedtext{$params{page}}->{$params{id}}) {
		return "[[paste ".sprintf(gettext('no text was copied in this page with id %s'), $params{id})."]]";
	}

	return IkiWiki::preprocess($params{page}, $params{destpage}, 
		IkiWiki::filter($params{page}, $params{destpage}, $savedtext{$params{page}}->{$params{id}}));
} # }}}

1;
