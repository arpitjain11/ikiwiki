#!/usr/bin/perl
# .po as a wiki page type
# inspired by the GPL'd po4a-translate,
# which is Copyright 2002, 2003, 2004 by Martin Quinson (mquinson#debian.org)
package IkiWiki::Plugin::po;

use warnings;
use strict;
use IkiWiki 2.00;
use Encode;
use Locale::Po4a::Chooser;
use File::Temp;

sub import {
	hook(type => "getsetup", id => "po", call => \&getsetup);
	hook(type => "checkconfig", id => "po", call => \&checkconfig);
	hook(type => "scan", id => "po", call => \&scan);
	hook(type => "targetpage", id => "po", call => \&targetpage);
	hook(type => "tweakurlpath", id => "po", call => \&tweakurlpath);
	hook(type => "tweakbestlink", id => "po", call => \&tweakbestlink);
	hook(type => "filter", id => "po", call => \&filter);
	hook(type => "htmlize", id => "po", call => \&htmlize);
}

sub getsetup () { #{{{
	return
		plugin => {
			safe => 0,
			rebuild => 1, # format plugin
		},
		po_master_language => {
			type => "string",
			example => {
				'code' => 'en',
				'name' => 'English'
			},
			description => "master language (non-PO files)",
			safe => 1,
			rebuild => 1,
		},
		po_slave_languages => {
			type => "string",
			example => {'fr' => { 'name' => 'Français' },
				    'es' => { 'name' => 'Castellano' },
				    'de' => { 'name' => 'Deutsch' },
			},
			description => "slave languages (PO files)",
			safe => 1,
			rebuild => 1,
		},
		po_translatable_pages => {
			type => "pagespec",
			example => "!*/Discussion",
			description => "PageSpec controlling which pages are translatable",
			link => "ikiwiki/PageSpec",
			safe => 1,
			rebuild => 1,
		},
		po_link_to => {
			type => "string",
			example => "current",
			description => "internal linking behavior (default/current/negotiated)",
			safe => 1,
			rebuild => 1,
		},
} #}}}

sub checkconfig () { #{{{
	foreach my $field (qw{po_master_language po_slave_languages}) {
		if (! exists $config{$field} || ! defined $config{$field}) {
			error(sprintf(gettext("Must specify %s"), $field));
		}
	}
	if (! exists $config{po_link_to} ||
	    ! defined $config{po_link_to}) {
	    $config{po_link_to}="default";
	}
	if (! exists $config{po_translatable_pages} ||
	    ! defined $config{po_translatable_pages}) {
	    $config{po_translatable_pages}="";
	}
	if ($config{po_link_to} eq "negotiated" && ! $config{usedirs}) {
		error(gettext("po_link_to=negotiated requires usedirs to be set"));
	}
} #}}}

sub scan (@) { #{{{
	my %params=@_;
	my $page=$params{page};

	# FIXME: cache (or memoize) the list of translatable/translation pages,
	# and/or istranslation/istranslated results
} #}}}

sub targetpage (@) { #{{{
	my %params = @_;
        my $page=$params{page};
        my $ext=$params{ext};

	if (istranslation($page)) {
		my ($masterpage, $lang) = ($page =~ /(.*)[.]([a-z]{2})$/);
		if (! $config{usedirs} || $page eq 'index') {
			return $masterpage . "." . $lang . "." . $ext;
		}
		else {
			return $masterpage . "/index." . $lang . "." . $ext;
		}
	}
	elsif (istranslatable($page)) {
		if (! $config{usedirs} || $page eq 'index') {
			return $page . "." . $config{po_master_language}{code} . "." . $ext;
		}
		else {
			return $page . "/index." . $config{po_master_language}{code} . "." . $ext;
		}
	}
	return;
} #}}}

sub tweakurlpath ($) { #{{{
	my %params = @_;
	my $url=$params{url};
	if ($config{po_link_to} eq "negotiated") {
		$url =~ s!/index.$config{po_master_language}{code}.$config{htmlext}$!/!;
	}
	return $url;
} #}}}

sub tweakbestlink ($$) { #{{{
	my %params = @_;
	my $page=$params{page};
	my $link=$params{link};
	if ($config{po_link_to} eq "current"
	    && istranslatable($link)
	    && istranslation($page)) {
		my ($masterpage, $curlang) = ($page =~ /(.*)[.]([a-z]{2})$/);
		return $link . "." . $curlang;
	}
	return $link;
} #}}}

# We use filter to convert PO to the master page's type,
# since other plugins should not work on PO files
sub filter (@) { #{{{
	my %params = @_;
	my $page = $params{page};
	my $content = decode_utf8(encode_utf8($params{content}));

	# decide if this is a PO file that should be converted into a translated document,
	# and perform various sanity checks
	if (! istranslation($page)) {
		return $content;
	}

	my ($masterpage, $lang) = ($page =~ /(.*)[.]([a-z]{2})$/);
	my $file=srcfile(exists $params{file} ? $params{file} : $IkiWiki::pagesources{$page});
	my $masterfile = srcfile($pagesources{$masterpage});
	my (@pos,@masters);
	push @pos,$file;
	push @masters,$masterfile;
	my %options = (
			"markdown" => (pagetype($masterfile) eq 'mdwn') ? 1 : 0,
			);
	my $doc=Locale::Po4a::Chooser::new('text',%options);
	$doc->process(
		'po_in_name'	=> \@pos,
		'file_in_name'	=> \@masters,
		'file_in_charset'  => 'utf-8',
		'file_out_charset' => 'utf-8',
	) or error("[po/filter:$file]: failed to translate");
	my ($percent,$hit,$queries) = $doc->stats();
	my $tmpfh = File::Temp->new(TEMPLATE => "/tmp/ikiwiki-po-filter-out.XXXXXXXXXX");
	my $tmpout = $tmpfh->filename;
	$doc->write($tmpout) or error("[po/filter:$file] could not write $tmpout");
	$content = readfile($tmpout) or error("[po/filter:$file] could not read $tmpout");
	return $content;
} #}}}

sub htmlize (@) { #{{{
	my %params=@_;
	my $page = $params{page};
	my $content = $params{content};
	my ($masterpage, $lang) = ($page =~ /(.*)[.]([a-z]{2})$/);
	my $masterfile = srcfile($pagesources{$masterpage});

	# force content to be htmlize'd as if it was the same type as the master page
	return IkiWiki::htmlize($page, $page, pagetype($masterfile), $content);
} #}}}

sub istranslatable ($) { #{{{
	my $page=shift;
	my $file=$pagesources{$page};

	if (! defined $file
	    || (defined pagetype($file) && pagetype($file) eq 'po')
	    || $file =~ /\.pot$/) {
		return 0;
	}
	return pagespec_match($page, $config{po_translatable_pages});
} #}}}

sub istranslation ($) { #{{{
	my $page=shift;
	my $file=$pagesources{$page};
	if (! defined $file) {
		return IkiWiki::FailReason->new("no file specified");
	}

	if (! defined $file
	    || ! defined pagetype($file)
 	    || ! pagetype($file) eq 'po'
	    || $file =~ /\.pot$/) {
		return 0;
	}

	my ($masterpage, $lang) = ($page =~ /(.*)[.]([a-z]{2})$/);
	if (! defined $masterpage || ! defined $lang
	    || ! (length($masterpage) > 0) || ! (length($lang) > 0)
	    || ! defined $pagesources{$masterpage}
	    || ! defined $config{po_slave_languages}{$lang}) {
		return 0;
	}

	return istranslatable($masterpage);
} #}}}


package IkiWiki::PageSpec;
use warnings;
use strict;
use IkiWiki 2.00;

sub match_istranslation ($;@) { #{{{
	my $page=shift;
	if (IkiWiki::Plugins::po::istranslation($page)) {
		return IkiWiki::SuccessReason->new("is a translation page");
	}
	else {
		return IkiWiki::FailReason->new("is not a translation page");
	}
} #}}}

sub match_istranslatable ($;@) { #{{{
	my $page=shift;
	if (IkiWiki::Plugins::po::istranslatable($page)) {
		return IkiWiki::SuccessReason->new("is set as translatable in po_translatable_pages");
	}
	else {
		return IkiWiki::FailReason->new("is not set as translatable in po_translatable_pages");
	}
} #}}}

1
