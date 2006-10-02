#!/usr/bin/perl -T
$ENV{PATH}="/usr/local/bin:/usr/bin:/bin";
delete @ENV{qw{IFS CDPATH ENV BASH_ENV}};

package IkiWiki;
our $version='unknown'; # VERSION_AUTOREPLACE done by Makefile, DNE

use warnings;
use strict;
use lib '.'; # For use without installation, removed by Makefile.
use IkiWiki;

sub usage () { #{{{
	die "usage: ikiwiki [options] source dest\n";
} #}}}

sub getconfig () { #{{{
	if (! exists $ENV{WRAPPED_OPTIONS}) {
		%config=defaultconfig();
		eval q{use Getopt::Long};
		Getopt::Long::Configure('pass_through');
		GetOptions(
			"setup|s=s" => \$config{setup},
			"wikiname=s" => \$config{wikiname},
			"verbose|v!" => \$config{verbose},
			"syslog!" => \$config{syslog},
			"rebuild!" => \$config{rebuild},
			"refresh!" => \$config{refresh},
			"render=s" => \$config{render},
			"wrappers!" => \$config{wrappers},
			"getctime" => \$config{getctime},
			"wrappermode=i" => \$config{wrappermode},
			"rcs=s" => \$config{rcs},
			"no-rcs" => sub { $config{rcs}="" },
			"anonok!" => \$config{anonok},
			"rss!" => \$config{rss},
			"cgi!" => \$config{cgi},
			"discussion!" => \$config{discussion},
			"w3mmode!" => \$config{w3mmode},
			"notify!" => \$config{notify},
			"url=s" => \$config{url},
			"cgiurl=s" => \$config{cgiurl},
			"historyurl=s" => \$config{historyurl},
			"diffurl=s" => \$config{diffurl},
			"svnrepo" => \$config{svnrepo},
			"svnpath" => \$config{svnpath},
			"adminemail=s" => \$config{adminemail},
			"timeformat=s" => \$config{timeformat},
			"sslcookie!" => \$config{sslcookie},
			"httpauth!" => \$config{httpauth},
			"exclude=s@" => sub {
				$config{wiki_file_prune_regexp}=qr/$config{wiki_file_prune_regexp}|$_[1]/;
			},
			"adminuser=s@" => sub {
				push @{$config{adminuser}}, $_[1]
			},
			"templatedir=s" => sub {
				$config{templatedir}=possibly_foolish_untaint($_[1])
			},
			"underlaydir=s" => sub {
				$config{underlaydir}=possibly_foolish_untaint($_[1])
			},
			"wrapper:s" => sub {
				$config{wrapper}=$_[1] ? $_[1] : "ikiwiki-wrap"
			},
			"plugin=s@" => sub {
				push @{$config{plugin}}, $_[1];
			},
			"disable-plugin=s@" => sub {
				$config{plugin}=[grep { $_ ne $_[1] } @{$config{plugin}}];
			},
			"pingurl" => sub {
				push @{$config{pingurl}}, $_[1];
			},
			"version" => sub {
				print "ikiwiki version $version\n";
				exit;
			},
		) || usage();

		if (! $config{setup} && ! $config{render}) {
			loadplugins();
			usage() unless @ARGV == 2;
			$config{srcdir} = possibly_foolish_untaint(shift @ARGV);
			$config{destdir} = possibly_foolish_untaint(shift @ARGV);
			checkconfig();
		}
	}
	else {
		# wrapper passes a full config structure in the environment
		# variable
		eval possibly_foolish_untaint($ENV{WRAPPED_OPTIONS});
		if ($@) {
			error("WRAPPED_OPTIONS: $@");
		}
		loadplugins();
		checkconfig();
	}
} #}}}

sub main () { #{{{
	getconfig();
	
	if ($config{cgi}) {
		lockwiki();
		loadindex();
		require IkiWiki::CGI;
		cgi();
	}
	elsif ($config{setup}) {
		require IkiWiki::Setup;
		setup();
	}
	elsif ($config{wrapper}) {
		lockwiki();
		require IkiWiki::Wrapper;
		gen_wrapper();
	}
	elsif ($config{render}) {
		require IkiWiki::Render;
		commandline_render();
	}
	else {
		lockwiki();
		loadindex();
		require IkiWiki::Render;
		rcs_update();
		refresh();
		rcs_notify() if $config{notify};
		saveindex();
	}
} #}}}

main;
