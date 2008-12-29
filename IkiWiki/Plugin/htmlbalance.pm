#!/usr/bin/perl
package IkiWiki::Plugin::htmlbalance;

# htmlbalance: Parse and re-serialize HTML to ensure balanced tags
#
# Copyright 2008 Simon McVittie <http://smcv.pseudorandom.co.uk/>
# Licensed under the GNU GPL, version 2, or any later version published by the
# Free Software Foundation

use warnings;
use strict;
use IkiWiki 3.00;
use HTML::Entities;

sub import {
	hook(type => "getsetup", id => "htmlbalance", call => \&getsetup);
	hook(type => "sanitize", id => "htmlbalance", call => \&sanitize);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub sanitize (@) {
	my %params=@_;
	my $ret = '';

	eval q{use HTML::TreeBuilder};
	error $@ if $@;
	my $tree = HTML::TreeBuilder->new();
	$tree->ignore_unknown(0);
	$tree->ignore_ignorable_whitespace(0);
	$tree->no_space_compacting(1);
	$tree->p_strict(1);
	$tree->store_comments(0);
	$tree->store_declarations(0);
	$tree->store_pis(0);
	$tree->parse_content($params{content});
	my @nodes = $tree->disembowel();
	foreach my $node (@nodes) {
		if (ref $node) {
			$ret .= $node->as_XML();
			chomp $ret;
			$node->delete();
		}
		else {
			$ret .= encode_entities($node);
		}
	}
	$tree->delete();
	return $ret;
}

1
