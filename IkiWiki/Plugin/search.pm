#!/usr/bin/perl
# xapian-omega search engine plugin
package IkiWiki::Plugin::search;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "checkconfig", id => "search", call => \&checkconfig);
	hook(type => "pagetemplate", id => "search", call => \&pagetemplate);
	hook(type => "delete", id => "search", call => \&delete);
	hook(type => "change", id => "search", call => \&change);
	hook(type => "cgi", id => "search", call => \&cgi);
} # }}}

sub checkconfig () { #{{{
	foreach my $required (qw(url cgiurl)) {
		if (! length $config{$required}) {
			error(sprintf(gettext("Must specify %s when using the search plugin"), $required));
		}
	}

	if (! exists $config{omega_cgi}) {
		$config{omega_cgi}="/usr/lib/cgi-bin/omega/omega";
	}
	
	if (! -e $config{wikistatedir}."/xapian" || $config{rebuild}) {
		writefile("omega.conf", $config{wikistatedir}."/xapian",
			"database_dir .\n".
			"template_dir ./templates\n");
		writefile("query", $config{wikistatedir}."/xapian/templates",
			IkiWiki::misctemplate(gettext("search"),
				readfile(IkiWiki::template_file("searchquery.tmpl"))));
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
			my $searchform = template("searchform.tmpl", blind_cache => 1);
			$searchform->param(searchaction => $config{cgiurl});
			$form=$searchform->output;
		}

		$template->param(searchform => $form);
	}
} #}}}

sub delete (@) { #{{{
	debug(gettext("cleaning xapian search index"));
} #}}}

sub change (@) { #{{{
	debug(gettext("updating xapian search index"));
} #}}}

sub cgi ($) { #{{{
	my $cgi=shift;

	if (defined $cgi->param('P')) {
		# only works for GET requests
		chdir("$config{wikistatedir}/xapian") || error("chdir: $!");
		$ENV{OMEGA_CONFIG_FILE}="./omega.conf";
		$ENV{CGIURL}=$config{cgiurl},
		exec($config{omega_cgi}) || error("$config{omega_cgi} failed: $!");
	}
} #}}}

1
