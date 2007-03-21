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
	delete $params{preview};

	eval q{use HTML::Entities};
	# Always dencode, even if encoding later, since it might not be
	# fully encoded.
	$value=decode_entities($value);

	if ($key eq 'link') {
		if (%params) {
			$meta{$page}.="<link href=\"".encode_entities($value)."\" ".
				join(" ", map { encode_entities($_)."=\"".encode_entities(decode_entities($params{$_}))."\"" } keys %params).
				" />\n";
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
		$permalink{$page}=$value;
		$meta{$page}.="<link rel=\"bookmark\" href=\"".encode_entities($value)."\" />\n";
	}
	elsif ($key eq 'date') {
		eval q{use Date::Parse};
		if (! $@) {
			my $time = str2time($value);
			$IkiWiki::pagectime{$page}=$time if defined $time;
		}
	}
	else {
		$meta{$page}.="<meta name=\"".encode_entities($key).
			"\" content=\"".encode_entities($value)."\" />\n";
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
