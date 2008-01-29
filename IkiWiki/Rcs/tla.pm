#!/usr/bin/perl

use warnings;
use strict;
use IkiWiki;

package IkiWiki;

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

sub rcs_update () { #{{{
	if (-d "$config{srcdir}/{arch}") {
		if (quiet_system("tla", "replay", "-d", $config{srcdir}) != 0) {
			warn("tla replay failed\n");
		}
	}
} #}}}

sub rcs_prepedit ($) { #{{{
	my $file=shift;

	if (-d "$config{srcdir}/{arch}") {
		# For Arch, return the tree-id of archive when
		# editing begins.
		my $rev=`tla tree-id $config{srcdir}`;
		return defined $rev ? $rev : "";
	}
} #}}}

sub rcs_commit ($$$;$$) { #{{{
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
		           "-L".possibly_foolish_untaint($message),
			   '-d', $config{srcdir}) != 0) {
			my $conflict=readfile("$config{srcdir}/$file");
			if (system("tla", "undo", "-n", "--quiet", "-d", "$config{srcdir}") != 0) {
				warn("tla undo failed\n");
			}
			return $conflict;
		}
	}
	return undef # success
} #}}}

sub rcs_add ($) { #{{{
	my $file=shift;

	if (-d "$config{srcdir}/{arch}") {
		if (quiet_system("tla", "add", "$config{srcdir}/$file") != 0) {
			warn("tla add failed\n");
		}
	}
} #}}}

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
		my $when = time - str2time($sdate, 'UTC');

		my $committype = "web";
		if (defined $summ && $summ =~ /$config{web_commit_regexp}/) {
			$user = defined $2 ? "$2" : "$3";
			$summ = $4;
		}
		else {
			$committype="tla";
		}

		my @message;
		push @message, { line => escapeHTML($summ) };

		my @pages;

		foreach my $file (@paths) {
			my $diffurl=$config{diffurl};
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

sub rcs_notify () { #{{{
	# FIXME: Not set
	if (! exists $ENV{ARCH_VERSION}) {
		error("ARCH_VERSION is not set, not running from tla post-commit hook, cannot send notifications");
	}
	my $rev=int(possibly_foolish_untaint($ENV{REV}));

	eval q{use Mail::Header};
	error($@) if $@;
	open(LOG, $ENV{"ARCH_LOG"});
	my $head = Mail::Header->new(\*LOG);
	close(LOG);

	my $user = $head->get("Creator");

	my $newfiles = $head->get("New-files");
	my $modfiles = $head->get("Modified-files");
	my $remfiles = $head->get("Removed-files");

	my @changed_pages = grep { !/(^.*\/)?\.arch-ids\/.*\.id$/ }
		split(/ /, "$newfiles $modfiles $remfiles .arch-ids/fake.id");

	require IkiWiki::UserInfo;
	send_commit_mails(
		sub {
			my $message = $head->get("Summary");
			if ($message =~ /$config{web_commit_regexp}/) {
				$user=defined $2 ? "$2" : "$3";
				$message=$4;
			}
		},
		sub {
			my $logs = `tla logs -d $config{srcdir}`;
			my @changesets = reverse split(/\n/, $logs);
			my $i;

			for($i=0;$i<$#changesets;$i++) {
				last if $changesets[$i] eq $rev;
			}
	
			my $revminusone = $changesets[$i+1];
			`tla diff -d $ENV{ARCH_TREE_ROOT} $revminusone`;
		}, $user, @changed_pages);
} #}}}

sub rcs_getctime ($) { #{{{
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
} #}}}

1
