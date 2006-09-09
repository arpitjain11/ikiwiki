#!/usr/bin/perl
# hyperestraier search engine plugin
package IkiWiki::Plugin::search;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	hook(type => "checkconfig", id => "hyperestraier",
		call => \&checkconfig);
	hook(type => "pagetemplate", id => "hyperestraier",
		call => \&pagetemplate);
	hook(type => "delete", id => "hyperestraier",
		call => \&delete);
	hook(type => "change", id => "hyperestraier",
		call => \&change);
	hook(type => "cgi", id => "hyperestraier",
		call => \&cgi);
} # }}}

sub checkconfig () { #{{{
	foreach my $required (qw(url cgiurl)) {
		if (! length $config{$required}) {
			error("Must specify $required when using the search plugin\n");
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
			my $searchform = template("searchform.tmpl", blind_cache => 1);
			$searchform->param(searchaction => $config{cgiurl});
			$form=$searchform->output;
		}

		$template->param(searchform => $form);
	}
} #}}}

sub delete (@) { #{{{
	debug("cleaning hyperestraier search index");
	estcmd("purge -cl");
	estcfg();
} #}}}

sub change (@) { #{{{
	debug("updating hyperestraier search index");
	estcmd("gather -cm -bc -cl -sd",
		map {
			Encode::encode_utf8($config{destdir}."/".$renderedfiles{pagename($_)})
		} @_
	);
	estcfg();
} #}}}

sub cgi ($) { #{{{
	my $cgi=shift;

	if (defined $cgi->param('phrase')) {
		# only works for GET requests
		chdir("$config{wikistatedir}/hyperestraier") || error("chdir: $!");
		exec("./".IkiWiki::basename($config{cgiurl})) || error("estseek.cgi failed");
	}
} #}}}

my $configured=0;
sub estcfg () { #{{{
	return if $configured;
	$configured=1;
	
	my $estdir="$config{wikistatedir}/hyperestraier";
	my $cgi=IkiWiki::basename($config{cgiurl});
	$cgi=~s/\..*$//;
	open(TEMPLATE, ">$estdir/$cgi.tmpl") ||
		error("write $estdir/$cgi.tmpl: $!");
	print TEMPLATE IkiWiki::misctemplate("search", 
		"<!--ESTFORM-->\n\n<!--ESTRESULT-->\n\n<!--ESTINFO-->\n\n");
	close TEMPLATE;
	open(TEMPLATE, ">$estdir/$cgi.conf") ||
		error("write $estdir/$cgi.conf: $!");
	my $template=template("estseek.conf");
	eval q{use Cwd 'abs_path'};
	$template->param(
		index => $estdir,
		tmplfile => "$estdir/$cgi.tmpl",
		destdir => IkiWiki::abs_path($config{destdir}),
		url => $config{url},
	);
	print TEMPLATE $template->output;
	close TEMPLATE;
	$cgi="$estdir/".IkiWiki::basename($config{cgiurl});
	unlink($cgi);
	symlink("/usr/lib/estraier/estseek.cgi", $cgi) ||
		error("symlink $cgi: $!");
} # }}}

sub estcmd ($;@) { #{{{
	my @params=split(' ', shift);
	push @params, "-cl", "$config{wikistatedir}/hyperestraier";
	if (@_) {
		push @params, "-";
	}
	
	my $pid=open(CHILD, "|-");
	if ($pid) {
		# parent
		foreach (@_) {
			print CHILD "$_\n";
		}
		close(CHILD) || error("estcmd @params exited nonzero: $?");
	}
	else {
		# child
		open(STDOUT, "/dev/null"); # shut it up (closing won't work)
		exec("estcmd", @params) || error("can't run estcmd");
	}
} #}}}

1
