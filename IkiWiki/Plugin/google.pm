#!/usr/bin/perl
package IkiWiki::Plugin::google;

use warnings;
use strict;
use IkiWiki 2.00;
use URI;

sub import { #{{{
	hook(type => "getsetup", id => "google", call => \&getsetup);
	hook(type => "checkconfig", id => "google", call => \&checkconfig);
	hook(type => "pagetemplate", id => "google", call => \&pagetemplate);
} # }}}

sub getsetup () { #{{{
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
} #}}}

sub checkconfig () { #{{{
	foreach my $required (qw(url)) {
		if (! length $config{$required}) {
			error(sprintf(gettext("Must specify %s when using the google search plugin"), $required));
		}
	}
} #}}}

my $form;
sub pagetemplate (@) { #{{{
	my %params=@_;
	my $page=$params{page};
	my $template=$params{template};

	# Add search box to page header.
	if ($template->query(name => "searchform")) {
		if (! defined $form) {
			my $searchform = template("googleform.tmpl", blind_cache => 1);
			$searchform->param(sitefqdn => URI->new($config{url})->host);
			$form=$searchform->output;
		}

		$template->param(searchform => $form);
	}
} #}}}

1
