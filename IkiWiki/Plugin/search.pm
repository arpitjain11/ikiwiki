#!/usr/bin/perl
# hyperestraier search engine plugin
package IkiWiki::Plugin::search;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "getopt", id => "hyperestraier",
		call => \&getopt);
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

sub getopt () { #{{{
        eval q{use Getopt::Long};
	error($@) if $@;
        Getopt::Long::Configure('pass_through');
        GetOptions("estseek=s" => \$config{estseek});
} #}}}

sub checkconfig () { #{{{
	foreach my $required (qw(url cgiurl)) {
		if (! length $config{$required}) {
			error(sprintf(gettext("Must specify %s when using the search plugin"), $required));
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
	debug(gettext("cleaning hyperestraier search index"));
	estcmd("purge -cl");
	estcfg();
} #}}}

sub change (@) { #{{{
	debug(gettext("updating hyperestraier search index"));
	estcmd("gather -cm -bc -cl -sd",
		map {
			map {
				Encode::encode_utf8($config{destdir}."/".$_)
			} @{$renderedfiles{pagename($_)}};
		} @_
	);
	estcfg();
} #}}}

sub cgi ($) { #{{{
	my $cgi=shift;

	if (defined $cgi->param('phrase') || defined $cgi->param("navi")) {
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

	my $newfile="$estdir/$cgi.tmpl.new";
	my $cleanup = sub { unlink($newfile) };
	open(TEMPLATE, ">:utf8", $newfile) || error("open $newfile: $!", $cleanup);
	print TEMPLATE IkiWiki::misctemplate("search", 
		"<!--ESTFORM-->\n\n<!--ESTRESULT-->\n\n<!--ESTINFO-->\n\n",
		forcebaseurl => IkiWiki::dirname($config{cgiurl})."/") ||
			error("write $newfile: $!", $cleanup);
	close TEMPLATE || error("save $newfile: $!", $cleanup);
	rename($newfile, "$estdir/$cgi.tmpl") ||
		error("rename $newfile: $!", $cleanup);
	
	$newfile="$estdir/$cgi.conf";
	open(TEMPLATE, ">$newfile") || error("open $newfile: $!", $cleanup);
	my $template=template("estseek.conf");
	eval q{use Cwd 'abs_path'};
	$template->param(
		index => $estdir,
		tmplfile => "$estdir/$cgi.tmpl",
		destdir => abs_path($config{destdir}),
		url => $config{url},
	);
	print TEMPLATE $template->output || error("write $newfile: $!", $cleanup);
	close TEMPLATE || error("save $newfile: $!", $cleanup);
	rename($newfile, "$estdir/$cgi.conf") ||
		error("rename $newfile: $!", $cleanup);

	$cgi="$estdir/".IkiWiki::basename($config{cgiurl});
	unlink($cgi);
	my $estseek = defined $config{estseek} ? $config{estseek} : '/usr/lib/estraier/estseek.cgi';
	symlink($estseek, $cgi) || error("symlink $estseek $cgi: $!");
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
		close(CHILD) || print STDERR "estcmd @params exited nonzero: $?\n";
	}
	else {
		# child
		open(STDOUT, "/dev/null"); # shut it up (closing won't work)
		exec("estcmd", @params) || error("can't run estcmd");
	}
} #}}}

1
