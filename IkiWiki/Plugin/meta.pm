#!/usr/bin/perl
# Ikiwiki metadata plugin.
package IkiWiki::Plugin::meta;

use warnings;
use strict;
use IkiWiki;

my %meta;
my %title;
my %permalink;
my %author;
my %authorurl;

sub import { #{{{
	hook(type => "preprocess", id => "meta", call => \&preprocess, scan => 1);
	hook(type => "filter", id => "meta", call => \&filter);
	hook(type => "pagetemplate", id => "meta", call => \&pagetemplate);
} # }}}

sub filter (@) { #{{{
	my %params=@_;
	
	$meta{$params{page}}='';

	return $params{content};
} # }}}

sub scrub ($) { #{{{
	if (IkiWiki::Plugin::htmlscrubber->can("sanitize")) {
		return IkiWiki::Plugin::htmlscrubber::sanitize(content => shift);
	}
	else {
		return shift;
	}
} #}}}

sub safeurl ($) { #{{{
	my $url=shift;
	if (exists $IkiWiki::Plugin::htmlscrubber::{safe_url_regexp} &&
	    defined $IkiWiki::Plugin::htmlscrubber::safe_url_regexp) {
		return $url=~/$IkiWiki::Plugin::htmlscrubber::safe_url_regexp/;
	}
	else {
		return 1;
	}
} #}}}

sub preprocess (@) { #{{{
	if (! @_) {
		return "";
	}
	my %params=@_;
	my $key=shift;
	my $value=$params{$key};
	delete $params{$key};
	my $page=$params{page};
	delete $params{page};
	delete $params{destpage};

	eval q{use HTML::Entities};
	# Always dencode, even if encoding later, since it might not be
	# fully encoded.
	$value=decode_entities($value);

	if ($key eq 'link') {
		if (%params) {
			$meta{$page}.=scrub("<link href=\"".encode_entities($value)."\" ".
				join(" ", map { encode_entities($_)."=\"".encode_entities(decode_entities($params{$_}))."\"" } keys %params).
				" />\n");
		}
		else {
			# hidden WikiLink
			push @{$links{$page}}, $value;
		}
	}
	elsif ($key eq 'title') {
		$title{$page}=encode_entities($value);
	}
	elsif ($key eq 'permalink') {
		if (safeurl($value)) {
			$permalink{$page}=$value;
			$meta{$page}.=scrub("<link rel=\"bookmark\" href=\"".encode_entities($value)."\" />\n");
		}
	}
	elsif ($key eq 'stylesheet') {
		my $rel=exists $params{rel} ? $params{rel} : "alternate stylesheet";
		my $title=exists $params{title} ? $params{title} : $value;
		# adding .css to the value prevents using any old web
		# editable page as a stylesheet
		my $stylesheet=bestlink($page, $value.".css");
		if (! length $stylesheet) {
			return "[[meta ".gettext("stylesheet not found")."]]";
		}
		$meta{$page}.='<link href="'.$stylesheet.
			'" rel="'.encode_entities($rel).
			'" title="'.encode_entities($title).
			"\" style=\"text/css\" />\n";
	}
	elsif ($key eq 'openid') {
		if (exists $params{server} && safeurl($params{server})) {
			$meta{$page}.='<link href="'.encode_entities($params{server}).
				"\" rel=\"openid.server\" />\n";
		}
		if (safeurl($value)) {
			$meta{$page}.='<link href="'.encode_entities($value).
				"\" rel=\"openid.delegate\" />\n";
		}
	}
	else {
		$meta{$page}.=scrub("<meta name=\"".encode_entities($key).
			"\" content=\"".encode_entities($value)."\" />\n");
		if ($key eq 'author') {
			$author{$page}=$value;
		}
		elsif ($key eq 'authorurl' && safeurl($value)) {
			$authorurl{$page}=$value;
		}
	}

	return "";
} # }}}

sub pagetemplate (@) { #{{{
	my %params=@_;
        my $page=$params{page};
        my $template=$params{template};

	$template->param(meta => $meta{$page})
		if exists $meta{$page} && $template->query(name => "meta");
	if (exists $title{$page} && $template->query(name => "title")) {
		$template->param(title => $title{$page});
		$template->param(title_overridden => 1);
	}
	$template->param(permalink => $permalink{$page})
		if exists $permalink{$page} && $template->query(name => "permalink");
	$template->param(author => $author{$page})
		if exists $author{$page} && $template->query(name => "author");
	$template->param(authorurl => $authorurl{$page})
		if exists $authorurl{$page} && $template->query(name => "authorurl");
	
} # }}}

1
