#!/usr/bin/perl
# .po as a wiki page type
package IkiWiki::Plugin::po;

use warnings;
use strict;
use IkiWiki 2.00;
use Encode;

sub import {
	hook(type => "getsetup", id => "po", call => \&getsetup);
	hook(type => "targetpage", id => "po", call => \&targetpage);
	hook(type => "filter", id => "po", call => \&filter);
	hook(type => "htmlize", id => "po", call => \&htmlize);
}

sub getsetup () { #{{{
	return
		plugin => {
			safe => 0,
			rebuild => 1, # format plugin
		},
		po_supported_languages => {
			type => "string",
			example => { 'fr' => { 'name' => 'Français' },
				    'es' => { 'name' => 'Castellano' },
				    'de' => { 'name' => 'Deutsch' },
			},
			safe => 1,
			rebuild => 1,
		},
} #}}}

sub targetpage (@) { #{{{
	my %params = @_;
        my $page=$params{page};
        my $ext=$params{ext};

	if (! IkiWiki::PageSpec::match_istranslation($page, $page)) {
		return;
	}

	my ($masterpage, $lang) = ($page =~ /(.*)[.]([a-z]{2})$/);
	if (! $config{usedirs} || $page eq 'index') {
		return $masterpage.".".$ext.".".$lang;
	}
	else {
		return $masterpage."/index.".$ext.".".$lang;
	}
} #}}}

# We use filter to convert PO to HTML, since the other plugins might do harm to it.
sub filter (@) { #{{{
	my %params = @_;
	my $content = decode_utf8(encode_utf8($params{content}));

	if (defined $pagesources{$params{page}} && $pagesources{$params{page}} =~ /\.po$/) {
		$content = "<pre>" . $content . "</pre>";
	}

	return $content;
} #}}}

# We need this to register the .po file extension
sub htmlize (@) { #{{{
	my %params=@_;
	return $params{content};
} #}}}

package IkiWiki::PageSpec;

sub match_istranslation ($;@) { #{{{
	my $page=shift;
	my $wanted=shift;

	my %params=@_;
	my $file=exists $params{file} ? $params{file} : $IkiWiki::pagesources{$page};
	if (! defined $file) {
		return IkiWiki::FailReason->new("no file specified");
	}

	if (! IkiWiki::pagetype($page) eq 'po') {
		return IkiWiki::FailReason->new("is not a PO file");
	}

	my ($masterpage, $lang) = ($page =~ /(.*)[.]([a-z]{2})$/);
	if (! defined $masterpage || ! defined $lang
	    || ! (length($masterpage) > 0) || ! (length($lang) > 0)) {
		return IkiWiki::FailReason->new("is not named like a translation file");
	}

	if (! defined $IkiWiki::pagesources{$masterpage}) {
		return IkiWiki::FailReason->new("the master page does not exist");
	}

	if (! defined $IkiWiki::config{po_supported_languages}{$lang}) {
		return IkiWiki::FailReason->new("language $lang is not supported");
	}

	return IkiWiki::SuccessReason->new("page $page is a translation");

} #}}}

1
