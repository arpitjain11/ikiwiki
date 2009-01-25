#!/usr/bin/perl
package IkiWiki::Plugin::blogspam;

use warnings;
use strict;
use IkiWiki 3.00;

my $defaulturl='http://test.blogspam.net:8888/';

sub import {
	hook(type => "getsetup", id => "blogspam",  call => \&getsetup);
	hook(type => "checkcontent", id => "blogspam", call => \&checkcontent);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
		},
		blogspam_pagespec => {
			type => 'pagespec',
			example => 'postcomment(*)',
			description => 'PageSpec of pages to check for spam',
			link => 'ikiwiki/PageSpec',
			safe => 1,
			rebuild => 0,
		},
		blogspam_options => {
			type => "string",
			example => "blacklist=1.2.3.4,blacklist=8.7.6.5,max-links=10",
			description => "options to send to blogspam server",
			link => "http://blogspam.net/api/testComment.html#options",
			safe => 1,
			rebuild => 0,
		},
		blogspam_server => {
			type => "string",
			default => $defaulturl,
			description => "blogspam server XML-RPC url",
			safe => 1,
			rebuild => 0,
		},
}

sub checkcontent (@) {
	my %params=@_;

	eval q{
		use RPC::XML;
		use RPC::XML::Client;
	};
	if ($@) {
		warn($@);
		return undef;
	}
	
 	if (exists $config{blogspam_pagespec}) {
		return undef
			if ! pagespec_match($params{page}, $config{blogspam_pagespec},
	                	location => $params{page});
	}

	my $url=$defaulturl;
	$url = $config{blogspam_server} if exists $config{blogspam_server};
	my $client = RPC::XML::Client->new($url);

	my @options = split(",", $config{blogspam_options})
		if exists $config{blogspam_options};

	# Allow short comments and whitespace-only edits, unless the user
	# has overridden min-words themselves.
	push @options, "min-words=0"
		unless grep /^min-words=/i, @options;
	# Wiki pages can have a lot of urls, unless the user specifically
	# wants to limit them.
	push @options, "exclude=lotsaurls"
		unless grep /^max-links/i, @options;
	# Unless the user specified a size check, disable such checking.
	push @options, "exclude=size"
		unless grep /^(?:max|min)-size/i, @options;
	# This test has absurd false positives on words like "alpha"
	# and "buy".
	push @options, "exclude=stopwords";

	my %req=(
		ip => $ENV{REMOTE_ADDR},
		comment => $params{content},
		subject => defined $params{subject} ? $params{subject} : "",
		name => defined $params{author} ? $params{author} : "",
		link => exists $params{url} ? $params{url} : "",
		options => join(",", @options),
		site => $config{url},
		version => "ikiwiki ".$IkiWiki::version,
	);
	my $res = $client->send_request('testComment', \%req);

	if (! ref $res || ! defined $res->value) {
		debug("failed to get response from blogspam server ($url)");
		return undef;
	}
	elsif ($res->value =~ /^SPAM:(.*)/) {
		eval q{use Data::Dumper};
		debug("blogspam server reports ".$res->value.": ".Dumper(\%req));
		return gettext("Sorry, but that looks like spam to <a href=\"http://blogspam.net/\">blogspam</a>: ").$1;
	}
	elsif ($res->value ne 'OK') {
		debug("blogspam server failure: ".$res->value);
		return undef;
	}
	else {
		return undef;
	}
}

1
