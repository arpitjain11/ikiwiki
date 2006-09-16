#!/usr/bin/perl

use warnings;
use strict;
use IkiWiki;
use POSIX qw(setlocale LC_CTYPE);

package IkiWiki;

my $tla_webcommit=qr/^web commit (by (\w+)|from (\d+\.\d+\.\d+\.\d+)):?(.*)/;

sub quiet_system (@) {
	# See Debian bug #385939.
	open (SAVEOUT, ">&STDOUT");
	close STDOUT;
	open (STDOUT, ">/dev/null");
	my $ret=system(@_);
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

sub rcs_commit ($$$) { #{{{
	my $file=shift;
	my $message=shift;
	my $rcstoken=shift;

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
	eval q{use Mail::Header};

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
		my $user = $head->get("Creator");

		my @paths = grep { !/^(.*\/)?\.arch-ids\/.*\.id$/ }
			split(/ /, "$newfiles $modfiles .arch-ids/fake.id");

		my $sdate = $head->get("Standard-date");
		my $when = time - str2time($sdate, 'UTC');

		my $committype = "web";
		if (defined $summ && $summ =~ /$tla_webcommit/) {
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
		push @ret, { rev => $change,
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
	open(LOG, $ENV{"ARCH_LOG"});
	my $head = Mail::Header->new(\*LOG);
	close(LOG);

	my $message = $head->get("Summary");
	my $user = $head->get("Creator");

	my $newfiles = $head->get("New-files");
	my $modfiles = $head->get("Modified-files");

	my @changed_pages = grep {!/(^.*\/)?\.arch-ids\/.*\.id$/} split(/ /,
		"$newfiles $modfiles");

	if ($message =~ /$tla_webcommit/) {
		$user=defined $2 ? "$2" : "$3";
		$message=$4;
	}

	require IkiWiki::UserInfo;
	my @email_recipients=commit_notify_list($user, @changed_pages);
	if (@email_recipients) {
		# TODO: if a commit spans multiple pages, this will send
		# subscribers a diff that might contain pages they did not
		# sign up for. Should separate the diff per page and
		# reassemble into one mail with just the pages subscribed to.
		my $logs = `tla logs -d $config{srcdir}`;
		my @changesets = reverse split(/\n/, $logs);
		my $i;

		for($i=0;$i<$#changesets;$i++) {
			last if $changesets[$i] eq $rev;
		}

		my $revminusone = $changesets[$i+1];
		my $diff=`tla diff -d $ENV{ARCH_TREE_ROOT} $revminusone`;

		my $subject="$config{wikiname} update of ";
		if (@changed_pages > 2) {
			$subject.="$changed_pages[0] $changed_pages[1] etc";
		}
		else {
			$subject.=join(" ", @changed_pages);
		}
		$subject.=" by $user";

		my $template=template("notifymail.tmpl");
		$template->param(
			wikiname => $config{wikiname},
			diff => $diff,
			user => $user,
			message => $message,
		);

		eval q{use Mail::Sendmail};
		foreach my $email (@email_recipients) {
			sendmail(
				To => $email,
				From => "$config{wikiname} <$config{adminemail}>",
				Subject => $subject,
				Message => $template->output,
			) or error("Failed to send update notification mail");
		}
	}
} #}}}

sub rcs_getctime ($) { #{{{
	my $file=shift;
	eval q{use Date::Parse};
	eval q{use Mail::Header};

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
