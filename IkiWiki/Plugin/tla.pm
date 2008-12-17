#!/usr/bin/perl
package IkiWiki::Plugin::tla;

use warnings;
use strict;
use IkiWiki;

sub import {
	hook(type => "checkconfig", id => "tla", call => \&checkconfig);
	hook(type => "getsetup", id => "tla", call => \&getsetup);
	hook(type => "rcs", id => "rcs_update", call => \&rcs_update);
	hook(type => "rcs", id => "rcs_prepedit", call => \&rcs_prepedit);
	hook(type => "rcs", id => "rcs_commit", call => \&rcs_commit);
	hook(type => "rcs", id => "rcs_commit_staged", call => \&rcs_commit_staged);
	hook(type => "rcs", id => "rcs_add", call => \&rcs_add);
	hook(type => "rcs", id => "rcs_remove", call => \&rcs_remove);
	hook(type => "rcs", id => "rcs_rename", call => \&rcs_rename);
	hook(type => "rcs", id => "rcs_recentchanges", call => \&rcs_recentchanges);
	hook(type => "rcs", id => "rcs_diff", call => \&rcs_diff);
	hook(type => "rcs", id => "rcs_getctime", call => \&rcs_getctime);
}

sub checkconfig () {
	if (defined $config{tla_wrapper} && length $config{tla_wrapper}) {
		push @{$config{wrappers}}, {
			wrapper => $config{tla_wrapper},
			wrappermode => (defined $config{tla_wrappermode} ? $config{tla_wrappermode} : "06755"),
		};
	}
}

sub getsetup () {
	return
		plugin => {
			safe => 0, # rcs plugin
			rebuild => undef,
		},
		tla_wrapper => {
			type => "string",
			#example => "", # TODO example
			description => "tla post-commit hook to generate",
			safe => 0, # file
			rebuild => 0,
		},
		tla_wrappermode => {
			type => "string",
			example => '06755',
			description => "mode for tla_wrapper (can safely be made suid)",
			safe => 0,
			rebuild => 0,
		},
		historyurl => {
			type => "string",
			#example => "", # TODO example
			description => "url to show file history ([[file]] substituted)",
			safe => 1,
			rebuild => 1,
		},
		diffurl => {
			type => "string",
			#example => "", # TODO example
			description => "url to show a diff ([[file]] and [[rev]] substituted)",
			safe => 1,
			rebuild => 1,
		},
}

sub quiet_system (@) {
	# See Debian bug #385939.
	open (SAVEOUT, ">&STDOUT");
	close STDOUT;
	open (STDOUT, ">/dev/null");
	my $ret=system(@_);
	close STDOUT;
	open (STDOUT, ">&SAVEOUT");
	close SAVEOUT;
	return $ret;
}

sub rcs_update () {
	if (-d "$config{srcdir}/{arch}") {
		if (quiet_system("tla", "replay", "-d", $config{srcdir}) != 0) {
			warn("tla replay failed\n");
		}
	}
}

sub rcs_prepedit ($) {
	my $file=shift;

	if (-d "$config{srcdir}/{arch}") {
		# For Arch, return the tree-id of archive when
		# editing begins.
		my $rev=`tla tree-id $config{srcdir}`;
		return defined $rev ? $rev : "";
	}
}

sub rcs_commit ($$$;$$) {
	my $file=shift;
	my $message=shift;
	my $rcstoken=shift;
	my $user=shift;
	my $ipaddr=shift;

	if (defined $user) {
		$message="web commit by $user".(length $message ? ": $message" : "");
	}
	elsif (defined $ipaddr) {
		$message="web commit from $ipaddr".(length $message ? ": $message" : "");
	}

	if (-d "$config{srcdir}/{arch}") {
		# Check to see if the page has been changed by someone
		# else since rcs_prepedit was called.
		my ($oldrev)=$rcstoken=~/^([A-Za-z0-9@\/._-]+)$/; # untaint
		my $rev=`tla tree-id $config{srcdir}`;
		if (defined $rev && defined $oldrev && $rev ne $oldrev) {
			# Merge their changes into the file that we've
			# changed.
			if (quiet_system("tla", "update", "-d",
			           "$config{srcdir}") != 0) {
				warn("tla update failed\n");
			}
		}

		if (quiet_system("tla", "commit",
		           "-L".IkiWiki::possibly_foolish_untaint($message),
			   '-d', $config{srcdir}) != 0) {
			my $conflict=readfile("$config{srcdir}/$file");
			if (system("tla", "undo", "-n", "--quiet", "-d", "$config{srcdir}") != 0) {
				warn("tla undo failed\n");
			}
			return $conflict;
		}
	}
	return undef # success
}

sub rcs_commit_staged ($$$) {
	# Commits all staged changes. Changes can be staged using rcs_add,
	# rcs_remove, and rcs_rename.
	my ($message, $user, $ipaddr)=@_;
	
	error("rcs_commit_staged not implemented for tla"); # TODO
}

sub rcs_add ($) {
	my $file=shift;

	if (-d "$config{srcdir}/{arch}") {
		if (quiet_system("tla", "add", "$config{srcdir}/$file") != 0) {
			warn("tla add failed\n");
		}
	}
}

sub rcs_remove ($) {
	my $file = shift;

	error("rcs_remove not implemented for tla"); # TODO
}

sub rcs_rename ($$) { # {{{a
	my ($src, $dest) = @_;

	error("rcs_rename not implemented for tla"); # TODO
}

sub rcs_recentchanges ($) {
	my $num=shift;
	my @ret;

	return unless -d "$config{srcdir}/{arch}";

	eval q{use Date::Parse};
	error($@) if $@;
	eval q{use Mail::Header};
	error($@) if $@;

	my $logs = `tla logs -d $config{srcdir}`;
	my @changesets = reverse split(/\n/, $logs);

	for (my $i=0; $i<$num && $i<$#changesets; $i++) {
		my ($change)=$changesets[$i]=~/^([A-Za-z0-9@\/._-]+)$/; # untaint

		open(LOG, "tla cat-log -d $config{srcdir} $change|");
		my $head = Mail::Header->new(\*LOG);
		close(LOG);

		my $rev = $head->get("Revision");
		my $summ = $head->get("Summary");
		my $newfiles = $head->get("New-files");
		my $modfiles = $head->get("Modified-files");
		my $remfiles = $head->get("Removed-files");
		my $user = $head->get("Creator");

		my @paths = grep { !/^(.*\/)?\.arch-ids\/.*\.id$/ }
			split(/ /, "$newfiles $modfiles .arch-ids/fake.id");

		my $sdate = $head->get("Standard-date");
		my $when = str2time($sdate, 'UTC');

		my $committype = "web";
		if (defined $summ && $summ =~ /$config{web_commit_regexp}/) {
			$user = defined $2 ? "$2" : "$3";
			$summ = $4;
		}
		else {
			$committype="tla";
		}

		my @message;
		push @message, { line => $summ };

		my @pages;

		foreach my $file (@paths) {
			my $diffurl=defined $config{diffurl} ? $config{diffurl} : "";
			$diffurl=~s/\[\[file\]\]/$file/g;
			$diffurl=~s/\[\[rev\]\]/$change/g;
			push @pages, {
				page => pagename($file),
				diffurl => $diffurl,
			} if length $file;
		}
		push @ret, {
			rev => $change,
			user => $user,
			committype => $committype,
			when => $when,
			message => [@message],
			pages => [@pages],
		} if @pages;

		last if $i == $num;
	}

	return @ret;
}

sub rcs_diff ($) {
	my $rev=shift;
	my $logs = `tla logs -d $config{srcdir}`;
	my @changesets = reverse split(/\n/, $logs);
	my $i;

	for($i=0;$i<$#changesets;$i++) {
		last if $changesets[$i] eq $rev;
	}

	my $revminusone = $changesets[$i+1];
	return `tla diff -d $config{srcdir} $revminusone`;
}

sub rcs_getctime ($) {
	my $file=shift;
	eval q{use Date::Parse};
	error($@) if $@;
	eval q{use Mail::Header};
	error($@) if $@;

	my $logs = `tla logs -d $config{srcdir}`;
	my @changesets = reverse split(/\n/, $logs);
	my $sdate;

	for (my $i=0; $i<$#changesets; $i++) {
		my $change = $changesets[$i];

		open(LOG, "tla cat-log -d $config{srcdir} $change|");
		my $head = Mail::Header->new(\*LOG);
		close(LOG);

		$sdate = $head->get("Standard-date");
		my $newfiles = $head->get("New-files");

		my ($lastcreation) = grep {/^$file$/} split(/ /, "$newfiles");
		last if defined($lastcreation);
	}

	my $date=str2time($sdate, 'UTC');
	debug("found ctime ".localtime($date)." for $file");
	return $date;
}

1
