#!/usr/bin/perl
# xapian-omega search engine plugin
package IkiWiki::Plugin::search;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "checkconfig", id => "search", call => \&checkconfig);
	hook(type => "pagetemplate", id => "search", call => \&pagetemplate);
	# run last so other needsbuild hooks can modify the list
	hook(type => "needsbuild", id => "search", call => \&needsbuild,
		last => 1);
	hook(type => "filter", id => "search", call => \&filter);
	hook(type => "delete", id => "search", call => \&delete);
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

my %toindex;
sub needsbuild ($) { #{{{
	%toindex = map { $_ => 1 } @{shift()};
} #}}}

sub filter (@) { #{{{
	my %params=@_;
	
	if ($params{page} eq $params{destpage} && $toindex{$params{page}}) {
		# index page
		my $db=xapiandb();
		my $doc=Search::Xapian::Document->new();
		my $title=$params{page};
		if (exists $pagestate{$params{page}}{meta} &&
		    exists $pagestate{$params{page}}{meta}{title}) {
			$title=$pagestate{$params{page}}{meta}{title};
		}

		# data used by omega
		$doc->set_data(
			"url=".urlto($params{page}, "")."\n".
			"sample=\n". # TODO
			"caption=$title\n".
			"modtime=$IkiWiki::pagemtime{$params{page}}\n".
			"size=".length($params{content})."\n"
		);

		my $tg = Search::Xapian::TermGenerator->new();
		$tg->set_stemmer(new Search::Xapian::Stem("english"));
		$tg->set_document($doc);
		$tg->index_text($params{page}, 2);
		$tg->index_text($title, 2);
		$tg->index_text($params{content}); # TODO html strip; preprocessor too

		my $pageterm=pageterm($params{page});
		$doc->add_term($pageterm);
		$db->replace_document_by_term($pageterm, $doc);
	}

	return $params{content};
} #}}}

sub delete (@) { #{{{
	my $db=xapiandb();
	foreach my $page (@_) {
		$db->delete_document_by_term(pageterm($page));
	}
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

sub pageterm ($) { #{{{
	my $page=shift;

	# TODO: check if > 255 char page names overflow term
	# length; use sha1 if so?
	return "P".$page;
} #}}}

my $db;
sub xapiandb () { #{{{
	if (! defined $db) {
		eval q{
			use Search::Xapian;
			use Search::Xapian::WritableDatabase;
		};
		error($@) if $@;
		$db=Search::Xapian::WritableDatabase->new($config{wikistatedir}."/xapian/default",
			Search::Xapian::DB_CREATE_OR_OPEN());
	}
	return $db;
} #}}}

1
