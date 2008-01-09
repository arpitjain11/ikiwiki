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

sub import { #{{{
	hook(type => "needsbuild", id => "meta", call => \&needsbuild);
	hook(type => "preprocess", id => "meta", call => \&preprocess, scan => 1);
	hook(type => "pagetemplate", id => "meta", call => \&pagetemplate);
} # }}}

sub needsbuild (@) { #{{{
	my $needsbuild=shift;
	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{meta}) {
			if (grep { $_ eq $pagesources{$page} } @$needsbuild) {
				# remove state, it will be re-added
				# if the preprocessor directive is still
				# there during the rebuild
				delete $pagestate{$page}{meta};
			}
		}
	}
}

sub scrub ($) { #{{{
	if (IkiWiki::Plugin::htmlscrubber->can("sanitize")) {
		return IkiWiki::Plugin::htmlscrubber::sanitize(content => shift);
	}
	else {
		return shift;
	}
} #}}}

sub htmlize ($$$) { #{{{
	my $page = shift;
	my $destpage = shift;
	my $text = shift;

	$text=IkiWiki::htmlize($page, pagetype($pagesources{$page}),
		IkiWiki::linkify($page, $destpage,
		IkiWiki::preprocess($page, $destpage, $text)));

	# hack to get rid of enclosing junk added by markdown
	$text=~s!^<p>!!;
	$text=~s!</p>$!!;
	chomp $text;

	return $text;
}

sub preprocess (@) { #{{{
	return "" unless @_;
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
	# Always decode, even if encoding later, since it might not be
	# fully encoded.
	$value=decode_entities($value);

	# Metadata collection that needs to happen during the scan pass.
	if ($key eq 'title') {
		$title{$page}=HTML::Entities::encode_numeric($value);
	}
	elsif ($key eq 'license') {
		push @{$meta{$page}}, '<link rel="license" href="#page_license" />';
		$license{$page}=$value;
		return "";
	}
	elsif ($key eq 'copyright') {
		push @{$meta{$page}}, '<link rel="copyright" href="#page_copyright" />';
		$copyright{$page}=$value;
		return "";
	}
	elsif ($key eq 'link' && ! %params) {
		# hidden WikiLink
		push @{$links{$page}}, $value;
		return "";
	}
	elsif ($key eq 'author') {
		$author{$page}=$value;
		# fallthorough
	}
	elsif ($key eq 'authorurl') {
		$authorurl{$page}=$value;
		# fallthrough
	}

	if (! defined wantarray) {
		# avoid collecting duplicate data during scan pass
		return;
	}

	# Metadata collection that happens only during preprocessing pass.
	if ($key eq 'date') {
		eval q{use Date::Parse};
		if (! $@) {
			my $time = str2time($value);
			$IkiWiki::pagectime{$page}=$time if defined $time;
		}
	}
	elsif ($key eq 'permalink') {
		$permalink{$page}=$value;
		push @{$meta{$page}}, scrub('<link rel="bookmark" href="'.encode_entities($value).'" />');
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
		push @{$meta{$page}}, '<link href="'.urlto($stylesheet, $page).
			'" rel="'.encode_entities($rel).
			'" title="'.encode_entities($title).
			"\" type=\"text/css\" />";
	}
	elsif ($key eq 'openid') {
		if (exists $params{server}) {
			push @{$meta{$page}}, '<link href="'.encode_entities($params{server}).
				'" rel="openid.server" />';
		}
		push @{$meta{$page}}, '<link href="'.encode_entities($value).
			'" rel="openid.delegate" />';
	}
	elsif ($key eq 'redir') {
		return "" if $page ne $destpage;
		my $safe=0;
		if ($value !~ /^\w+:\/\//) {
			my ($redir_page, $redir_anchor) = split /\#/, $value;

			add_depends($page, $redir_page);
			my $link=bestlink($page, $redir_page);
			if (! length $link) {
				return "[[meta ".gettext("redir page not found")."]]";
			}

			$value=urlto($link, $page);
			$value.='#'.$redir_anchor if defined $redir_anchor;
			$safe=1;

			# redir cycle detection
			$pagestate{$page}{meta}{redir}=$link;
			my $at=$page;
			my %seen;
			while (exists $pagestate{$at}{meta}{redir}) {
				if ($seen{$at}) {
					return "[[meta ".gettext("redir cycle is not allowed")."]]";
				}
				$seen{$at}=1;
				$at=$pagestate{$at}{meta}{redir};
			}
		}
		else {
			$value=encode_entities($value);
		}
		my $delay=int(exists $params{delay} ? $params{delay} : 0);
		my $redir="<meta http-equiv=\"refresh\" content=\"$delay; URL=$value\">";
		if (! $safe) {
			$redir=scrub($redir);
		}
		push @{$meta{$page}}, $redir;
	}
	elsif ($key eq 'link') {
		if (%params) {
			$meta{$page}.=scrub("<link href=\"".encode_entities($value)."\" ".
				join(" ", map {
					encode_entities($_)."=\"".encode_entities(decode_entities($params{$_}))."\""
				} keys %params).
				" />\n");
		}
	}
	else {
		push @{$meta{$page}}, scrub('<meta name="'.encode_entities($key).
			'" content="'.encode_entities($value).'" />');
	}

	return "";
} # }}}

sub pagetemplate (@) { #{{{
	my %params=@_;
        my $page=$params{page};
        my $destpage=$params{destpage};
        my $template=$params{template};

	if (exists $meta{$page} && $template->query(name => "meta")) {
		# avoid duplicate meta lines
		my %seen;
		$template->param(meta => join("\n", grep { (! $seen{$_}) && ($seen{$_}=1) } @{$meta{$page}}));
	}
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

	if (exists $license{$page} && $template->query(name => "license") &&
	    ($page eq $destpage || ! exists $license{$destpage} ||
	     $license{$page} ne $license{$destpage})) {
		$template->param(license => htmlize($page, $destpage, $license{$page}));
	}
	if (exists $copyright{$page} && $template->query(name => "copyright") &&
	    ($page eq $destpage || ! exists $copyright{$destpage} ||
	     $copyright{$page} ne $copyright{$destpage})) {
		$template->param(copyright => htmlize($page, $destpage, $copyright{$page}));
	}
} # }}}

1
