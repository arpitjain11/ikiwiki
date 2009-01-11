#!/usr/bin/perl
package IkiWiki::Plugin::pinger;

use warnings;
use strict;
use IkiWiki 3.00;

my %pages;
my $pinged=0;

sub import {
	hook(type => "getsetup", id => "pinger", call => \&getsetup);
	hook(type => "needsbuild", id => "pinger", call => \&needsbuild);
	hook(type => "preprocess", id => "ping", call => \&preprocess);
	hook(type => "delete", id => "pinger", call => \&ping);
	hook(type => "change", id => "pinger", call => \&ping);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
		},
		pinger_timeout => {
			type => "integer",
			example => 15,
			description => "how many seconds to try pinging before timing out",
			safe => 1,
			rebuild => 0,
		},
}

sub needsbuild (@) {
	my $needsbuild=shift;
	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{pinger}) {
			$pages{$page}=1;
			if (exists $pagesources{$page} &&
			    grep { $_ eq $pagesources{$page} } @$needsbuild) {
				# remove state, will be re-added if
				# the ping directive is still present
				# on rebuild.
				delete $pagestate{$page}{pinger};
			}
		}
	}
}

sub preprocess (@) {
	my %params=@_;
	if (! exists $params{from} || ! exists $params{to}) {
		error gettext("requires 'from' and 'to' parameters");
	}
	if ($params{from} eq $config{url}) {
		$pagestate{$params{destpage}}{pinger}{$params{to}}=1;
		$pages{$params{destpage}}=1;
		return sprintf(gettext("Will ping %s"), $params{to});
	}
	else {
		return sprintf(gettext("Ignoring ping directive for wiki %s (this wiki is %s)"), $params{from}, $config{url});
	}
}

sub ping {
	if (! $pinged && %pages) {
		$pinged=1;
		
		my $ua;
		eval q{use LWPx::ParanoidAgent};
		if (!$@) {
			$ua=LWPx::ParanoidAgent->new;
		}
		else {
			eval q{use LWP};
			if ($@) {
				debug(gettext("LWP not found, not pinging"));
				return;
			}
			$ua=LWP::UserAgent->new;
		}
		$ua->timeout($config{pinger_timeout} || 15);
		
		# daemonise here so slow pings don't slow down wiki updates
		defined(my $pid = fork) or error("Can't fork: $!");
		return if $pid;
		chdir '/';
		open STDIN, '/dev/null';
		open STDOUT, '>/dev/null';
		POSIX::setsid() or error("Can't start a new session: $!");
		open STDERR, '>&STDOUT' or error("Can't dup stdout: $!");
		
		# Don't need to keep a lock on the wiki as a daemon.
		IkiWiki::unlockwiki();
		
		my %urls;
		foreach my $page (%pages) {
			if (exists $pagestate{$page}{pinger}) {
				$urls{$_}=1 foreach keys %{$pagestate{$page}{pinger}};
			}
		}
		foreach my $url (keys %urls) {
			# Try to avoid pinging ourselves. If this check
			# fails, it's not the end of the world, since we
			# only ping when a page was changed, so a ping loop
			# will still be avoided.
			next if $url=~/^\Q$config{cgiurl}\E/;
			
			$ua->get($url);
		}
		
		exit 0;
	}
}

1
