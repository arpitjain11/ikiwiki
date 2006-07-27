#!/usr/bin/perl
# Ikiwiki metadata plugin.
package IkiWiki::Plugin::meta;

use warnings;
use strict;
use IkiWiki;

my %meta;
my %title;

sub import { #{{{
	IkiWiki::hook(type => "preprocess", id => "meta", 
		call => \&preprocess);
	IkiWiki::hook(type => "pagetemplate", id => "meta", 
		call => \&pagetemplate);
} # }}}

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

	eval q{use CGI 'escapeHTML'};

	if ($key eq 'link') {
		if (%params) {
			$meta{$page}='' unless exists $meta{$page};
			$meta{$page}.="<link href=\"".escapeHTML($value)."\" ".
				join(" ", map { escapeHTML("$_=\"$params{$_}\"") } keys %params).
				" />\n";
		}
		else {
			# hidden WikiLink
			push @{$IkiWiki::links{$page}}, $value;
		}
	}
	elsif ($key eq 'title') {
		$title{$page}=escapeHTML($value);
	}
	else {
		$meta{$page}='' unless exists $meta{$page};
		$meta{$page}.="<meta name=\"".escapeHTML($key)."\" content=\"".escapeHTML($value)."\" />\n";
	}

	return "";
} # }}}

sub pagetemplate (@) { #{{{
	my %params=@_;
        my $page=$params{page};
        my $template=$params{template};

	$template->param(meta => $meta{$page})
		if exists $meta{$page} && $template->query(name => "meta");
	$template->param(title => $title{$page})
		if exists $title{$page} && $template->query(name => "title");
} # }}}

1
