#!/usr/bin/perl
package IkiWiki::Plugin::google;

use warnings;
use strict;
use IkiWiki 3.00;
use URI;

my $host;

sub import {
	hook(type => "getsetup", id => "google", call => \&getsetup);
	hook(type => "checkconfig", id => "google", call => \&checkconfig);
	hook(type => "pagetemplate", id => "google", call => \&pagetemplate);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
}

sub checkconfig () {
	if (! length $config{url}) {
		error(sprintf(gettext("Must specify %s when using the google search plugin"), "url"));
	}
	my $uri=URI->new($config{url});
	if (! $uri || ! defined $uri->host) {
		error(gettext("Failed to parse url, cannot determine domain name"));
	}
	$host=$uri->host;
}

my $form;
sub pagetemplate (@) {
	my %params=@_;
	my $page=$params{page};
	my $template=$params{template};

	# Add search box to page header.
	if ($template->query(name => "searchform")) {
		if (! defined $form) {
			my $searchform = template("googleform.tmpl", blind_cache => 1);
			$searchform->param(sitefqdn => $host);
			$form=$searchform->output;
		}

		$template->param(searchform => $form);
	}
}

1
