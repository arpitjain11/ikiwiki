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

sub import (@) { #{{{
	my %setup=@_;

	# Sanitize this to avoid problimatic directory names.
	$setup{wikiname}=~s/[^-A-Za-z0-9_] //g;
	if (! length $setup{wikiname}) {
		die "you must enter a wikiname\n";
	}

	# Avoid overwriting any existing files.
	foreach my $key (qw{srcdir destdir repository setupfile}) {
		next unless exists $setup{$key};
		my $add="";
		while (-e $setup{$key}.$add) {
			$add=1 if ! $add;
			$add++;
		}
		$setup{$key}.=$add;
	}

	print "\n\nSetting up $setup{wikiname} ...\n";

	# Set up the repository.
	mkpath($setup{srcdir}) || die "mkdir $setup{srcdir}: $!";
	delete $setup{repository} if ! $setup{rcs} || $setup{rcs}=~/bzr|mercurial/;
	if ($setup{rcs}) {
		my @params=($setup{rcs}, $setup{srcdir});
		push @params, $setup{repository} if exists $setup{repository};
		if (system("ikiwiki-makerepo", @params) != 0) {
			die "failed: ikiwiki-makerepo @params";
		}
	}

	# Generate setup file.
	my @params=(
		"--dumpsetup", $setup{setupfile},
		"--wikiname", $setup{wikiname},
		"--url", $setup{url},
		"--cgiurl", $setup{cgiurl}
	);
	push @params, "--rcs", $setup{rcs} if $setup{rcs};
	if (exists $setup{add_plugins}) {
		foreach my $plugin (@{$setup{add_plugins}}) {
			push @params, "--plugin", $plugin;
		}
	}
	if (exists $setup{disable_plugins}) {
		foreach my $plugin (@{$setup{disable_plugins}}) {
			push @params, "--disable-plugin", $plugin;
		}
	}
	foreach my $key (keys %setup) {
		next if $key =~ /^(disable_plugins|add_plugins|setupfile|wikiname|url|cgiurl||srcdir|destdir|repository)$/;
		push @params, "--set", "$key=$setup{$key}";
	}
	if (system("ikiwiki", @params, $setup{srcdir}, $setup{destdir}) != 0) {
		die "failed: ikiwiki @params";
	}

	# Build the wiki.
	mkpath($setup{destdir}) || die "mkdir $setup{destdir}: $!";
	if (system("ikiwiki", "--setup", $setup{setupfile}) != 0) {
		die "ikiwiki --setup $setup{setupfile} failed";
	}

	# Done!
	print "\n\nSuccessfully set up $setup{wikiname}:\n";
	foreach my $key (qw{url srcdir destdir repository setupfile}) {
		next unless exists $setup{$key};
		my $value=$setup{$key};
		$value=~s/^\Q$ENV{HOME}\E\//~\//;
		print "\t$key: ".(" " x (10 - length($key)))." $value\n";
	}
	exit 0;
} #}}}

1
