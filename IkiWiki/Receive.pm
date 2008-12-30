#!/usr/bin/perl

package IkiWiki::Receive;

use warnings;
use strict;
use IkiWiki;

sub getuser () {
	my $user=(getpwuid(exists $ENV{CALLER_UID} ? $ENV{CALLER_UID} : $<))[0];
	if (! defined $user) {
		error("cannot determine username for $<");
	}
	return $user;
}

sub trusted () {
	my $user=getuser();
	return ! ref $config{untrusted_committers} ||
		! grep { $_ eq $user } @{$config{untrusted_committers}};
}

sub gen_wrapper () {
	# Test for commits from untrusted committers in the wrapper, to
	# avoid loading ikiwiki at all for trusted commits.

	my $ret=<<"EOF";
	{
		int u=getuid();
EOF
	$ret.="\t\tif ( ".
		join("&&", map {
			my $uid=getpwnam($_);
			if (! defined $uid) {
				error(sprintf(gettext("cannot determine id of untrusted committer %s"), $_));
			}
			"u != $uid";
		} @{$config{untrusted_committers}}).
		") exit(0);\n";
	$ret.=<<"EOF";
		asprintf(&s, "CALLER_UID=%i", u);
		newenviron[i++]=s;
	}
EOF
	return $ret;
}

sub test () {
	exit 0 if trusted();
	
	IkiWiki::lockwiki();
	IkiWiki::loadindex();
	
	# Dummy up a cgi environment to use when calling check_canedit
	# and friends.
	eval q{use CGI};
	error($@) if $@;
	my $cgi=CGI->new;
	$ENV{REMOTE_ADDR}='unknown' unless exists $ENV{REMOTE_ADDR};

	# And dummy up a session object.
	require IkiWiki::CGI;
	my $session=IkiWiki::cgi_getsession($cgi);
	$session->param("name", getuser());
	# Make sure whatever user was authed is in the
	# userinfo db.
	require IkiWiki::UserInfo;
	if (! IkiWiki::userinfo_get($session->param("name"), "regdate")) {
		IkiWiki::userinfo_setall($session->param("name"), {
			email => "",
			password => "",
			regdate => time,
		}) || error("failed adding user");
	}
	
	my %newfiles;

	foreach my $change (IkiWiki::rcs_receive()) {
		# This untaint is safe because we check file_pruned and
		# wiki_file_regexp.
		my ($file)=$change->{file}=~/$config{wiki_file_regexp}/;
		$file=IkiWiki::possibly_foolish_untaint($file);
		if (! defined $file || ! length $file ||
		    IkiWiki::file_pruned($file, $config{srcdir})) {
			error(gettext("bad file name %s"), $file);
		}

		my $type=pagetype($file);
		my $page=pagename($file) if defined $type;
		
		if ($change->{action} eq 'add') {
			$newfiles{$file}=1;
		}

		if ($change->{action} eq 'change' ||
		    $change->{action} eq 'add') {
			if (defined $page) {
				if (IkiWiki->can("check_canedit")) {
					IkiWiki::check_canedit($page, $cgi, $session);
					next;
				}
			}
			else {
				if (IkiWiki::Plugin::attachment->can("check_canattach")) {
					IkiWiki::Plugin::attachment::check_canattach($session, $file, $change->{path});
					next;
				}
			}
		}
		elsif ($change->{action} eq 'remove') {
			# check_canremove tests to see if the file is present
			# on disk. This will fail is a single commit adds a
			# file and then removes it again. Avoid the problem
			# by not testing the removal in such pairs of changes.
			# (The add is still tested, just to make sure that
			# no data is added to the repo that a web edit
			# could add.)
			next if $newfiles{$file};

			if (IkiWiki::Plugin::remove->can("check_canremove")) {
				IkiWiki::Plugin::remove::check_canremove(defined $page ? $page : $file, $cgi, $session);
				next;
			}
		}
		else {
			error "unknown action ".$change->{action};
		}
		
		error sprintf(gettext("you are not allowed to change %s"), $file);
	}

	exit 0;
}

1
