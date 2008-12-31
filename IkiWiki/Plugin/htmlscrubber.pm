#!/usr/bin/perl
package IkiWiki::Plugin::htmlscrubber;

use warnings;
use strict;
use IkiWiki 3.00;

# This regexp matches urls that are in a known safe scheme.
# Feel free to use it from other plugins.
our $safe_url_regexp;

sub import {
	hook(type => "getsetup", id => "htmlscrubber", call => \&getsetup);
	hook(type => "sanitize", id => "htmlscrubber", call => \&sanitize);

	# Only known uri schemes are allowed to avoid all the ways of
	# embedding javascrpt.
	# List at http://en.wikipedia.org/wiki/URI_scheme
	my $uri_schemes=join("|", map quotemeta,
		# IANA registered schemes
		"http", "https", "ftp", "mailto", "file", "telnet", "gopher",
		"aaa", "aaas", "acap", 	"cap", "cid", "crid", 
		"dav", "dict", "dns", "fax", "go", "h323", "im", "imap",
		"ldap", "mid", "news", "nfs", "nntp", "pop", "pres",
		"sip", "sips", "snmp", "tel", "urn", "wais", "xmpp",
		"z39.50r", "z39.50s",
		# Selected unofficial schemes
		"aim", "callto", "cvs", "ed2k", "feed", "fish", "gg",
		"irc", "ircs", "lastfm", "ldaps", "magnet", "mms",
		"msnim", "notes", "rsync", "secondlife", "skype", "ssh",
		"sftp", "smb", "sms", "snews", "webcal", "ymsgr",
	);
	# data is a special case. Allow data:image/*, but
	# disallow data:text/javascript and everything else.
	$safe_url_regexp=qr/^(?:(?:$uri_schemes):|data:image\/|[^:]+(?:$|\/))/i;
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
		htmlscrubber_skip => {
			type => "pagespec",
			example => "!*/Discussion",
			description => "PageSpec specifying pages not to scrub",
			link => "ikiwiki/PageSpec",
			safe => 1,
			rebuild => undef,
		},
}

sub sanitize (@) {
	my %params=@_;

	if (exists $config{htmlscrubber_skip} &&
	    length $config{htmlscrubber_skip} &&
	    exists $params{destpage} &&
	    pagespec_match($params{destpage}, $config{htmlscrubber_skip})) {
		return $params{content};
	}

	return scrubber()->scrub($params{content});
}

my $_scrubber;
sub scrubber {
	return $_scrubber if defined $_scrubber;

	eval q{use HTML::Scrubber};
	error($@) if $@;
	# Lists based on http://feedparser.org/docs/html-sanitization.html
	# With html 5 video and audio tags added.
	$_scrubber = HTML::Scrubber->new(
		allow => [qw{
			a abbr acronym address area b big blockquote br br/
			button caption center cite code col colgroup dd del
			dfn dir div dl dt em fieldset font form h1 h2 h3 h4
			h5 h6 hr hr/ i img input ins kbd label legend li map
			menu ol optgroup option p p/ pre q s samp select small
			span strike strong sub sup table tbody td textarea
			tfoot th thead tr tt u ul var
			video audio
		}],
		default => [undef, { (
			map { $_ => 1 } qw{
				abbr accept accept-charset accesskey
				align alt axis border cellpadding cellspacing
				char charoff charset checked class
				clear cols colspan color compact coords
				datetime dir disabled enctype for frame
				headers height hreflang hspace id ismap
				label lang maxlength media method
				multiple name nohref noshade nowrap prompt
				readonly rel rev rows rowspan rules scope
				selected shape size span start summary
				tabindex target title type valign
				value vspace width
				autoplay loopstart loopend end
				playcount controls 
			} ),
			"/" => 1, # emit proper <hr /> XHTML
			href => $safe_url_regexp,
			src => $safe_url_regexp,
			action => $safe_url_regexp,
			cite => $safe_url_regexp,
			longdesc => $safe_url_regexp,
			poster => $safe_url_regexp,
			usemap => $safe_url_regexp,
		}],
	);
	return $_scrubber;
}

1
