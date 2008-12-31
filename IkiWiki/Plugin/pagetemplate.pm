#!/usr/bin/perl
package IkiWiki::Plugin::pagetemplate;

use warnings;
use strict;
use IkiWiki 3.00;

my %templates;

sub import {
	hook(type => "getsetup", id => "pagetemplate", call => \&getsetup);
	hook(type => "preprocess", id => "pagetemplate", call => \&preprocess);
	hook(type => "templatefile", id => "pagetemplate", call => \&templatefile);
}

sub getsetup () {
	return 
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess (@) {
	my %params=@_;

	if (! exists $params{template} ||
	    $params{template} !~ /^[-A-Za-z0-9._+]+$/ ||
	    ! defined IkiWiki::template_file($params{template})) {
		 error gettext("bad or missing template")
	}

	if ($params{page} eq $params{destpage}) {
		$templates{$params{page}}=$params{template};
	}

	return "";
}

sub templatefile (@) {
	my %params=@_;

	if (exists $templates{$params{page}}) {
		return $templates{$params{page}};
	}
	
	return undef;
}

1
