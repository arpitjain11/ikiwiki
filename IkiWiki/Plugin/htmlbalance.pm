#!/usr/bin/perl
package IkiWiki::Plugin::htmlbalance;

# htmlbalance: Parse and re-serialize HTML to ensure balanced tags
#
# Copyright 2008 Simon McVittie <http://smcv.pseudorandom.co.uk/>
# Licensed under the GNU GPL, version 2, or any later version published by the
# Free Software Foundation

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "getsetup", id => "htmlbalance", call => \&getsetup);
	hook(type => "sanitize", id => "htmlbalance", call => \&sanitize);
} # }}}

sub getsetup () { #{{{
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
} #}}}

sub sanitize (@) { #{{{
	my %params=@_;
	my $ret = '';

	eval {
		use HTML::TreeBuilder;
		use XML::Atom::Util qw(encode_xml);
	};

	if ($@) {
		error($@);
		return $params{content};
	}

	my $tree = HTML::TreeBuilder->new_from_content($params{content});
	my @nodes = $tree->disembowel();
	foreach my $node (@nodes) {
		if (ref $node) {
			$ret .= $node->as_XML();
			chomp $ret;
			$node->delete();
		}
		else {
			$ret .= encode_xml($node);
		}
	}
	$tree->delete();
	return $ret;
} # }}}

1
