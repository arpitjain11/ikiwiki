#!/usr/bin/perl

package IkiWiki;

use warnings;
use strict;
use File::Spec;
use Data::Dumper;
use IkiWiki;

sub gen_wrapper () {
	$config{srcdir}=File::Spec->rel2abs($config{srcdir});
	$config{destdir}=File::Spec->rel2abs($config{destdir});
	my $this=File::Spec->rel2abs($0);
	if (! -x $this) {
		error(sprintf(gettext("%s doesn't seem to be executable"), $this));
	}

	if ($config{setup}) {
		error(gettext("cannot create a wrapper that uses a setup file"));
	}
	my $wrapper=possibly_foolish_untaint($config{wrapper});
	if (! defined $wrapper || ! length $wrapper) {
		error(gettext("wrapper filename not specified"));
	}
	delete $config{wrapper};
	
	my @envsave;
	push @envsave, qw{REMOTE_ADDR QUERY_STRING REQUEST_METHOD REQUEST_URI
	               CONTENT_TYPE CONTENT_LENGTH GATEWAY_INTERFACE
		       HTTP_COOKIE REMOTE_USER HTTPS REDIRECT_STATUS
		       REDIRECT_URL} if $config{cgi};
	my $envsave="";
	foreach my $var (@envsave) {
		$envsave.=<<"EOF";
	if ((s=getenv("$var")))
		addenv("$var", s);
EOF
	}

	my $test_receive="";
	if ($config{test_receive}) {
		require IkiWiki::Receive;
		$test_receive=IkiWiki::Receive::gen_wrapper();
	}

	my $check_commit_hook="";
	my $pre_exec="";
	if ($config{post_commit}) {
		# Optimise checking !commit_hook_enabled() , 
		# so that ikiwiki does not have to be started if the
		# hook is disabled.
		#
		# Note that perl's flock may be implemented using fcntl
		# or lockf on some systems. If so, and if there is no
		# interop between the locking systems, the true C flock will
		# always succeed, and this optimisation won't work.
		# The perl code will later correctly check the lock,
		# so the right thing will still happen, though without
		# the benefit of this optimisation.
		$check_commit_hook=<<"EOF";
	{
		int fd=open("$config{wikistatedir}/commitlock", O_CREAT | O_RDWR, 0666);
		if (fd != -1) {
			if (flock(fd, LOCK_SH | LOCK_NB) != 0)
				exit(0);
			close(fd);
		}
	}
EOF
	}
	elsif ($config{cgi}) {
		# Avoid more than one ikiwiki cgi running at a time by
		# taking a cgi lock. Since ikiwiki uses several MB of
		# memory, a pile up of processes could cause thrashing
		# otherwise. The fd of the lock is stored in
		# IKIWIKI_CGILOCK_FD so unlockwiki can close it.
		$pre_exec=<<"EOF";
	{
		int fd=open("$config{wikistatedir}/cgilock", O_CREAT | O_RDWR, 0666);
		if (fd != -1 && flock(fd, LOCK_EX) == 0) {
			char *fd_s;
			asprintf(&fd_s, "%i", fd);
			setenv("IKIWIKI_CGILOCK_FD", fd_s, 1);
		}
	}
EOF
	}

	$Data::Dumper::Indent=0; # no newlines
	my $configstring=Data::Dumper->Dump([\%config], ['*config']);
	$configstring=~s/\\/\\\\/g;
	$configstring=~s/"/\\"/g;
	$configstring=~s/\n/\\n/g;
	
	writefile(basename("$wrapper.c"), dirname($wrapper), <<"EOF");
/* A wrapper for ikiwiki, can be safely made suid. */
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>

extern char **environ;
char *newenviron[$#envsave+6];
int i=0;

addenv(char *var, char *val) {
	char *s=malloc(strlen(var)+1+strlen(val)+1);
	if (!s)
		perror("malloc");
	sprintf(s, "%s=%s", var, val);
	newenviron[i++]=s;
}

int main (int argc, char **argv) {
	char *s;

$check_commit_hook
$test_receive
$envsave
	newenviron[i++]="HOME=$ENV{HOME}";
	newenviron[i++]="WRAPPED_OPTIONS=$configstring";
	newenviron[i]=NULL;
	environ=newenviron;

	if (setregid(getegid(), -1) != 0 &&
	    setregid(getegid(), -1) != 0) {
		perror("failed to drop real gid");
		exit(1);
	}
	if (setreuid(geteuid(), -1) != 0 &&
	    setreuid(geteuid(), -1) != 0) {
		perror("failed to drop real uid");
		exit(1);
	}

$pre_exec
	execl("$this", "$this", NULL);
	perror("exec $this");
	exit(1);
}
EOF
	close OUT;

	my $cc=exists $ENV{CC} ? possibly_foolish_untaint($ENV{CC}) : 'cc';
	if (system($cc, "$wrapper.c", "-o", "$wrapper.new") != 0) {
		#translators: The parameter is a C filename.
		error(sprintf(gettext("failed to compile %s"), "$wrapper.c"));
	}
	unlink("$wrapper.c");
	if (defined $config{wrappergroup}) {
		my $gid=(getgrnam($config{wrappergroup}))[2];
		if (! defined $gid) {
			error(sprintf("bad wrappergroup"));
		}
		if (! chown(-1, $gid, "$wrapper.new")) {
			error("chown $wrapper.new: $!");
		}
	}
	if (defined $config{wrappermode} &&
	    ! chmod(oct($config{wrappermode}), "$wrapper.new")) {
		error("chmod $wrapper.new: $!");
	}
	if (! rename("$wrapper.new", $wrapper)) {
		error("rename $wrapper.new $wrapper: $!");
	}
	#translators: The parameter is a filename.
	printf(gettext("successfully generated %s"), $wrapper);
	print "\n";
}

1
