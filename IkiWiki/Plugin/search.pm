#!/usr/bin/perl
# hyperestraier search engine plugin
package IkiWiki::Plugin::search;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	IkiWiki::hook(type => "checkconfig", id => "hyperestraier",
		call => \&checkconfig);
	IkiWiki::hook(type => "delete", id => "hyperestraier",
		call => \&delete);
	IkiWiki::hook(type => "render", id => "hyperestraier",
		call => \&render);
	IkiWiki::hook(type => "cgi", id => "hyperestraier",
		call => \&cgi);
} # }}}

sub checkconfig () { #{{{
	foreach my $required (qw(url cgiurl)) {
		if (! length $IkiWiki::config{$required}) {
			IkiWiki::error("Must specify $required when using the search plugin\n");
		}
	}

	$IkiWiki::config{headercontent}.=qq{
<form method="get" action="$IkiWiki::config{cgiurl}" id="searchform">
<div>
<input type="text" name="phrase" value="" size="16" />
<input type="hidden" name="enc" value="UTF-8" />
<input type="hidden" name="do" value="hyperestraier" />
</div>
</form>
};
} #}}}

sub delete (@) { #{{{
	IkiWiki::debug("cleaning hyperestraier search index");
	IkiWiki::estcmd("purge -cl");
	IkiWiki::estcfg();
} #}}}

sub render (@) { #{{{
	IkiWiki::debug("updating hyperestraier search index");
	IkiWiki::estcmd("gather -cm -bc -cl -sd",
		map {
			$IkiWiki::config{destdir}."/".$IkiWiki::renderedfiles{IkiWiki::pagename($_)}
		} @_
	);
	IkiWiki::estcfg();
} #}}}

sub cgi ($) { #{{{
	my $cgi=shift;

	if (defined $cgi->param('phrase')) {
		# only works for GET requests
		chdir("$IkiWiki::config{wikistatedir}/hyperestraier") || IkiWiki::error("chdir: $!");
		exec("./".IkiWiki::basename($IkiWiki::config{cgiurl})) || IkiWiki::error("estseek.cgi failed");
	}
} #}}}

# Easier to keep these in the IkiWiki namespace.
package IkiWiki;

my $configured=0;
sub estcfg () { #{{{
	return if $configured;
	$configured=1;
	
	my $estdir="$config{wikistatedir}/hyperestraier";
	my $cgi=basename($config{cgiurl});
	$cgi=~s/\..*$//;
	open(TEMPLATE, ">$estdir/$cgi.tmpl") ||
		error("write $estdir/$cgi.tmpl: $!");
	print TEMPLATE misctemplate("search", 
		"<!--ESTFORM-->\n\n<!--ESTRESULT-->\n\n<!--ESTINFO-->\n\n");
	close TEMPLATE;
	open(TEMPLATE, ">$estdir/$cgi.conf") ||
		error("write $estdir/$cgi.conf: $!");
	my $template=HTML::Template->new(
		filename => "$config{templatedir}/estseek.conf"
	);
	eval q{use Cwd 'abs_path'};
	$template->param(
		index => $estdir,
		tmplfile => "$estdir/$cgi.tmpl",
		destdir => abs_path($config{destdir}),
		url => $config{url},
	);
	print TEMPLATE $template->output;
	close TEMPLATE;
	$cgi="$estdir/".basename($config{cgiurl});
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
