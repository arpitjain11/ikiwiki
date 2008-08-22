#!/usr/bin/perl
# Ikiwiki setup automator.

package IkiWiki::Setup::Automator;

use warnings;
use strict;
use IkiWiki;
use IkiWiki::UserInfo;
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
		error gettext("you must enter a wikiname (that contains alphanumerics)");
	}

	# Avoid overwriting any existing files.
	foreach my $key (qw{srcdir destdir repository dumpsetup}) {
		next unless exists $config{$key};
		my $add="";
		while (-e $add.$config{$key}) {
			$add=1 if ! $add;
			$add++;
		}
		$config{$key}=$add.$config{$key};
	}
	
	# Set up wrapper
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
		else {
			error sprintf(gettext("unsupported revision control system %s"),
			       	$config{rcs});
		}
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
			error gettext("failed to set up the repository with ikiwiki-makerepo");
		}
	}

	# Generate setup file.
	require IkiWiki::Setup;
	IkiWiki::Setup::dump($config{dumpsetup});

	# Build the wiki, but w/o wrappers, so it's not live yet.
	mkpath($config{destdir}) || die "mkdir $config{destdir}: $!";
	if (system("ikiwiki", "--refresh", "--setup", $config{dumpsetup}) != 0) {
		die "ikiwiki --refresh --setup $config{dumpsetup} failed";
	}

	# Create admin user(s).
	foreach my $admin (@{$config{adminuser}}) {
		next if $admin=~/^http\?:\/\//; # openid
		
		# Prompt for password w/o echo.
		system('stty -echo 2>/dev/null');
		local $|=1;
		print "\n\nCreating wiki admin $admin ...\n";
		print "Choose a password: ";
		chomp(my $password=<STDIN>);
		print "\n\n\n";
		system('stty sane 2>/dev/null');

		if (IkiWiki::userinfo_setall($admin, { regdate => time }) &&
		    IkiWiki::Plugin::passwordauth::setpassword($admin, $password)) {
			IkiWiki::userinfo_set($admin, "email", $config{adminemail}) if defined $config{adminemail};
		}
		else {
			error("problem setting up $admin user");
		}
	}
	
	# Add wrappers, make live.
	if (system("ikiwiki", "--wrappers", "--setup", $config{dumpsetup}) != 0) {
		die "ikiwiki --wrappers --setup $config{dumpsetup} failed";
	}

	# Add it to the wikilist.
	mkpath("$ENV{HOME}/.ikiwiki");
	open (WIKILIST, ">>$ENV{HOME}/.ikiwiki/wikilist") || die "$ENV{HOME}/.ikiwiki/wikilist: $!";
	print WIKILIST "$ENV{USER} $config{dumpsetup}\n";
	close WIKILIST;
	if (system("ikiwiki-update-wikilist") != 0) {
		print STDERR "** Failed to add you to the system wikilist file.\n";
		print STDERR "** (Probably ikiwiki-update-wikilist is not SUID root.)\n";
		print STDERR "** Your wiki will not be automatically updated when ikiwiki is upgraded.\n";
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
