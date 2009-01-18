#!/usr/bin/perl
# Ikiwiki metadata plugin.
package IkiWiki::Plugin::meta;

use warnings;
use strict;
use IkiWiki 3.00;

my %metaheaders;

sub import {
	hook(type => "getsetup", id => "meta", call => \&getsetup);
	hook(type => "needsbuild", id => "meta", call => \&needsbuild);
	hook(type => "preprocess", id => "meta", call => \&preprocess, scan => 1);
	hook(type => "pagetemplate", id => "meta", call => \&pagetemplate);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub needsbuild (@) {
	my $needsbuild=shift;
	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{meta}) {
			if (exists $pagesources{$page} &&
			    grep { $_ eq $pagesources{$page} } @$needsbuild) {
				# remove state, it will be re-added
				# if the preprocessor directive is still
				# there during the rebuild
				delete $pagestate{$page}{meta};
			}
		}
	}
}

sub scrub ($$) {
	if (IkiWiki::Plugin::htmlscrubber->can("sanitize")) {
		return IkiWiki::Plugin::htmlscrubber::sanitize(
			content => shift, destpage => shift);
	}
	else {
		return shift;
	}
}

sub safeurl ($) {
	my $url=shift;
	if (exists $IkiWiki::Plugin::htmlscrubber::{safe_url_regexp} &&
	    defined $IkiWiki::Plugin::htmlscrubber::safe_url_regexp) {
		return $url=~/$IkiWiki::Plugin::htmlscrubber::safe_url_regexp/;
	}
	else {
		return 1;
	}
}

sub htmlize ($$$) {
	my $page = shift;
	my $destpage = shift;

	return IkiWiki::htmlize($page, $destpage, pagetype($pagesources{$page}),
		IkiWiki::linkify($page, $destpage,
		IkiWiki::preprocess($page, $destpage, shift)));
}

sub preprocess (@) {
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
		$pagestate{$page}{meta}{title}=HTML::Entities::encode_numeric($value);
		# fallthrough
	}
	elsif ($key eq 'description') {
		$pagestate{$page}{meta}{description}=HTML::Entities::encode_numeric($value);
		# fallthrough
	}
	elsif ($key eq 'guid') {
		$pagestate{$page}{meta}{guid}=HTML::Entities::encode_numeric($value);
		# fallthrough
	}
	elsif ($key eq 'license') {
		push @{$metaheaders{$page}}, '<link rel="license" href="#page_license" />';
		$pagestate{$page}{meta}{license}=$value;
		return "";
	}
	elsif ($key eq 'copyright') {
		push @{$metaheaders{$page}}, '<link rel="copyright" href="#page_copyright" />';
		$pagestate{$page}{meta}{copyright}=$value;
		return "";
	}
	elsif ($key eq 'link' && ! %params) {
		# hidden WikiLink
		push @{$links{$page}}, $value;
		return "";
	}
	elsif ($key eq 'author') {
		$pagestate{$page}{meta}{author}=$value;
		# fallthorough
	}
	elsif ($key eq 'authorurl') {
		$pagestate{$page}{meta}{authorurl}=$value if safeurl($value);
		# fallthrough
	}
	elsif ($key eq 'date') {
		eval q{use Date::Parse};
		if (! $@) {
			my $time = str2time($value);
			$IkiWiki::pagectime{$page}=$time if defined $time;
		}
	}
	elsif ($key eq 'updated') {
		eval q{use Date::Parse};
		if (! $@) {
			my $time = str2time($value);
			$pagestate{$page}{meta}{updated}=$time if defined $time;
		}
	}

	if (! defined wantarray) {
		# avoid collecting duplicate data during scan pass
		return;
	}

	# Metadata collection that happens only during preprocessing pass.
	if ($key eq 'permalink') {
		if (safeurl($value)) {
			$pagestate{$page}{meta}{permalink}=$value;
			push @{$metaheaders{$page}}, scrub('<link rel="bookmark" href="'.encode_entities($value).'" />', $destpage);
		}
	}
	elsif ($key eq 'stylesheet') {
		my $rel=exists $params{rel} ? $params{rel} : "alternate stylesheet";
		my $title=exists $params{title} ? $params{title} : $value;
		# adding .css to the value prevents using any old web
		# editable page as a stylesheet
		my $stylesheet=bestlink($page, $value.".css");
		if (! length $stylesheet) {
			error gettext("stylesheet not found")
		}
		push @{$metaheaders{$page}}, '<link href="'.urlto($stylesheet, $page).
			'" rel="'.encode_entities($rel).
			'" title="'.encode_entities($title).
			"\" type=\"text/css\" />";
	}
	elsif ($key eq 'openid') {
		if (exists $params{server} && safeurl($params{server})) {
			push @{$metaheaders{$page}}, '<link href="'.encode_entities($params{server}).
				'" rel="openid.server" />';
			push @{$metaheaders{$page}}, '<link href="'.encode_entities($params{server}).
				'" rel="openid2.provider" />';
		}
		if (safeurl($value)) {
			push @{$metaheaders{$page}}, '<link href="'.encode_entities($value).
				'" rel="openid.delegate" />';
			push @{$metaheaders{$page}}, '<link href="'.encode_entities($value).
				'" rel="openid2.local_id" />';
		}
		if (exists $params{"xrds-location"} && safeurl($params{"xrds-location"})) {
			push @{$metaheaders{$page}}, '<meta http-equiv="X-XRDS-Location"'.
				'content="'.encode_entities($params{"xrds-location"}).'" />';
		}
	}
	elsif ($key eq 'redir') {
		return "" if $page ne $destpage;
		my $safe=0;
		if ($value !~ /^\w+:\/\//) {
			my ($redir_page, $redir_anchor) = split /\#/, $value;

			add_depends($page, $redir_page);
			my $link=bestlink($page, $redir_page);
			if (! length $link) {
				error gettext("redir page not found")
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
					error gettext("redir cycle is not allowed")
				}
				$seen{$at}=1;
				$at=$pagestate{$at}{meta}{redir};
			}
		}
		else {
			$value=encode_entities($value);
		}
		my $delay=int(exists $params{delay} ? $params{delay} : 0);
		my $redir="<meta http-equiv=\"refresh\" content=\"$delay; URL=$value\" />";
		if (! $safe) {
			$redir=scrub($redir, $destpage);
		}
		push @{$metaheaders{$page}}, $redir;
	}
	elsif ($key eq 'link') {
		if (%params) {
			push @{$metaheaders{$page}}, scrub("<link href=\"".encode_entities($value)."\" ".
				join(" ", map {
					encode_entities($_)."=\"".encode_entities(decode_entities($params{$_}))."\""
				} keys %params).
				" />\n", $destpage);
		}
	}
	elsif ($key eq 'robots') {
		push @{$metaheaders{$page}}, '<meta name="robots"'.
			' content="'.encode_entities($value).'" />';
	}
	else {
		push @{$metaheaders{$page}}, scrub('<meta name="'.encode_entities($key).
			'" content="'.encode_entities($value).'" />', $destpage);
	}

	return "";
}

sub pagetemplate (@) {
	my %params=@_;
        my $page=$params{page};
        my $destpage=$params{destpage};
        my $template=$params{template};

	if (exists $metaheaders{$page} && $template->query(name => "meta")) {
		# avoid duplicate meta lines
		my %seen;
		$template->param(meta => join("\n", grep { (! $seen{$_}) && ($seen{$_}=1) } @{$metaheaders{$page}}));
	}
	if (exists $pagestate{$page}{meta}{title} && $template->query(name => "title")) {
		$template->param(title => $pagestate{$page}{meta}{title});
		$template->param(title_overridden => 1);
	}

	foreach my $field (qw{author authorurl permalink}) {
		$template->param($field => $pagestate{$page}{meta}{$field})
			if exists $pagestate{$page}{meta}{$field} && $template->query(name => $field);
	}

	foreach my $field (qw{license copyright}) {
		if (exists $pagestate{$page}{meta}{$field} && $template->query(name => $field) &&
		    ($page eq $destpage || ! exists $pagestate{$destpage}{meta}{$field} ||
		     $pagestate{$page}{meta}{$field} ne $pagestate{$destpage}{meta}{$field})) {
			$template->param($field => htmlize($page, $destpage, $pagestate{$page}{meta}{$field}));
		}
	}
}

sub match {
	my $field=shift;
	my $page=shift;
	
	# turn glob into a safe regexp
	my $re=IkiWiki::glob2re(shift);

	my $val;
	if (exists $pagestate{$page}{meta}{$field}) {
		$val=$pagestate{$page}{meta}{$field};
	}
	elsif ($field eq 'title') {
		$val = pagetitle($page);
	}

	if (defined $val) {
		if ($val=~/^$re$/i) {
			return IkiWiki::SuccessReason->new("$re matches $field of $page");
		}
		else {
			return IkiWiki::FailReason->new("$re does not match $field of $page");
		}
	}
	else {
		return IkiWiki::FailReason->new("$page does not have a $field");
	}
}

package IkiWiki::PageSpec;

sub match_title ($$;@) {
	IkiWiki::Plugin::meta::match("title", @_);	
}

sub match_author ($$;@) {
	IkiWiki::Plugin::meta::match("author", @_);
}

sub match_authorurl ($$;@) {
	IkiWiki::Plugin::meta::match("authorurl", @_);
}

sub match_license ($$;@) {
	IkiWiki::Plugin::meta::match("license", @_);
}

sub match_copyright ($$;@) {
	IkiWiki::Plugin::meta::match("copyright", @_);
}

1
