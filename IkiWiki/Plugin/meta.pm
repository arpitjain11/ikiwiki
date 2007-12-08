#!/usr/bin/perl
# Ikiwiki metadata plugin.
package IkiWiki::Plugin::meta;

use warnings;
use strict;
use IkiWiki 2.00;

my %meta;
my %title;
my %permalink;
my %author;
my %authorurl;
my %license;
my %copyright;
my %redirected;

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
	my $destpage=$params{destpage};
	delete $params{destpage};
	delete $params{preview};

	eval q{use HTML::Entities};
	# Always dencode, even if encoding later, since it might not be
	# fully encoded.
	$value=decode_entities($value);

	if ($key eq 'link') {
		if (%params) {
			$meta{$page}.=scrub("<link href=\"".encode_entities($value)."\" ".
				join(" ", map {
					encode_entities($_)."=\"".encode_entities(decode_entities($params{$_}))."\""
				} keys %params).
				" />\n");
		}
		else {
			# hidden WikiLink
			push @{$links{$page}}, $value;
		}
	}
	elsif ($key eq 'redir') {
		$redirected{$page}=1;
		my $safe=0;
		if ($value =~ /^$config{wiki_link_regexp}$/) {
			my $link=bestlink($page, $value);
			if (! length $link) {
				return "[[meta ".gettext("redir page not found")."]]";
			}
			if ($redirected{$link}) {
				# TODO this is a cheap way of avoiding
				# redir cycles, but it is really too strict.
				return "[[meta ".gettext("redir to page that itself redirs is not allowed")."]]";
			}
			$value=urlto($link, $destpage);
			$safe=1;
		}
		else {
			$value=encode_entities($value);
		}
		my $delay=int(exists $params{delay} ? $params{delay} : 0);
		my $redir="<meta http-equiv=\"refresh\" content=\"$delay; URL=$value\">";
		if (! $safe) {
			$redir=scrub($redir);
		}
		$meta{$page}.=$redir;
	}
	elsif ($key eq 'title') {
		$title{$page}=HTML::Entities::encode_numeric($value);
	}
	elsif ($key eq 'permalink') {
		$permalink{$page}=$value;
		$meta{$page}.=scrub("<link rel=\"bookmark\" href=\"".encode_entities($value)."\" />\n");
	}
	elsif ($key eq 'date') {
		eval q{use Date::Parse};
		if (! $@) {
			my $time = str2time($value);
			$IkiWiki::pagectime{$page}=$time if defined $time;
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
		$meta{$page}.='<link href="'.urlto($stylesheet, $page).
			'" rel="'.encode_entities($rel).
			'" title="'.encode_entities($title).
			"\" type=\"text/css\" />\n";
	}
	elsif ($key eq 'openid') {
		if (exists $params{server}) {
			$meta{$page}.='<link href="'.encode_entities($params{server}).
				"\" rel=\"openid.server\" />\n";
		}
		$meta{$page}.='<link href="'.encode_entities($value).
			"\" rel=\"openid.delegate\" />\n";
	}
	elsif ($key eq 'license') {
		$meta{$page}.="<link rel=\"license\" href=\"#page_license\" />\n";
		$license{$page}=$value;
	}
	elsif ($key eq 'copyright') {
		$meta{$page}.="<link rel=\"copyright\" href=\"#page_copyright\" />\n";
		$copyright{$page}=$value;
	}
	else {
		$meta{$page}.=scrub("<meta name=\"".encode_entities($key).
			"\" content=\"".encode_entities($value)."\" />\n");
		if ($key eq 'author') {
			$author{$page}=$value;
		}
		elsif ($key eq 'authorurl') {
			$authorurl{$page}=$value;
		}
	}

	return "";
} # }}}

sub pagetemplate (@) { #{{{
	my %params=@_;
        my $page=$params{page};
        my $destpage=$params{destpage};
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
		
	if ($page ne $destpage &&
	    ((exists $license{$page}   && ! exists $license{$destpage}) ||
	     (exists $copyright{$page} && ! exists $copyright{$destpage}))) {
		# Force a scan of the destpage to get its copyright/license
		# info. If the info is declared after an inline, it will
		# otherwise not be available at this point.
		IkiWiki::scan($pagesources{$destpage});
	}

	if (exists $license{$page} && $template->query(name => "license") &&
	    ($page eq $destpage || ! exists $license{$destpage} ||
	     $license{$page} ne $license{$destpage})) {
		$template->param(license => IkiWiki::linkify($page, $destpage, $license{$page}));
	}
	if (exists $copyright{$page} && $template->query(name => "copyright") &&
	    ($page eq $destpage || ! exists $copyright{$destpage} ||
	     $copyright{$page} ne $copyright{$destpage})) {
		$template->param(copyright => IkiWiki::linkify($page, $destpage, $copyright{$page}));
	}
} # }}}

1
