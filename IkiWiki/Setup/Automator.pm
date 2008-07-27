#!/usr/bin/perl
# Ikiwiki setup automator.

package IkiWiki::Setup::Automator;

use warnings;
use strict;
use IkiWiki;
use Term::ReadLine;
use File::Path;

sub ask ($$) { #{{{
	my ($question, $default)=@_;

	my $r=Term::ReadLine->new("ikiwiki");
	$r->readline($question." ", $default);
} #}}}

sub prettydir ($) { #{{{
	my $dir=shift;
	$dir=~s/^\Q$ENV{HOME}\E\//~\//;
	return $dir;
} #}}}

sub import (@) { #{{{
	my $this=shift;
	IkiWiki::Setup::merge({@_});

	# Sanitize this to avoid problimatic directory names.
	$config{wikiname}=~s/[^-A-Za-z0-9_] //g;
	if (! length $config{wikiname}) {
		die "you must enter a wikiname\n";
	}

	# Avoid overwriting any existing files.
	foreach my $key (qw{srcdir destdir repository dumpsetup}) {
		next unless exists $config{$key};
		my $add="";
		while (-e $config{$key}.$add) {
			$add=1 if ! $add;
			$add++;
		}
		$config{$key}.=$add;
	}

	IkiWiki::checkconfig();

	print "\n\nSetting up $config{wikiname} ...\n";

	# Set up the repository.
	mkpath($config{srcdir}) || die "mkdir $config{srcdir}: $!";
	delete $config{repository} if ! $config{rcs} || $config{rcs}=~/bzr|mercurial/;
	if ($config{rcs}) {
		my @params=($config{rcs}, $config{srcdir});
		push @params, $config{repository} if exists $config{repository};
		if (system("ikiwiki-makerepo", @params) != 0) {
			die "failed: ikiwiki-makerepo @params";
		}
	}

	# Generate setup file.
	require IkiWiki::Setup;
	if ($config{rcs}) {
		if ($config{rcs} eq 'git') {
			$config{git_wrapper}=$config{repository}."/hooks/post-update";
		}
		elsif ($config{rcs} eq 'svn') {
			$config{svn_wrapper}=$config{repository}."/hooks/post-commit";
		}
		elsif ($config{rcs} eq 'bzr') {
			# TODO
		}
		elsif ($config{rcs} eq 'mercurial') {
			# TODO
		}
	}
	IkiWiki::Setup::dump($config{dumpsetup});

	# Build the wiki.
	mkpath($config{destdir}) || die "mkdir $config{destdir}: $!";
	if (system("ikiwiki", "--setup", $config{dumpsetup}) != 0) {
		die "ikiwiki --setup $config{dumpsetup} failed";
	}

	# Done!
	print "\n\nSuccessfully set up $config{wikiname}:\n";
	foreach my $key (qw{url srcdir destdir repository}) {
		next unless exists $config{$key};
		print "\t$key: ".(" " x (10 - length($key)))." ".
			prettydir($config{$key})."\n";
	}
	print "To modify settings, edit ".prettydir($config{dumpsetup})." and then run:\n";
	print "	ikiwiki -setup ".prettydir($config{dumpsetup})."\n";
	exit 0;
} #}}}

1
