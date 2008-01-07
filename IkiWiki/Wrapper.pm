#!/usr/bin/perl

use warnings;
use strict;
use Cwd q{abs_path};
use Data::Dumper ;
use IkiWiki;

package IkiWiki;

sub gen_wrapper () { #{{{
	$config{srcdir}=abs_path($config{srcdir});
	$config{destdir}=abs_path($config{destdir});
	my $this=abs_path($0);
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
		       HTTP_COOKIE REMOTE_USER} if $config{cgi};
	my $envsave="";
	foreach my $var (@envsave) {
		$envsave.=<<"EOF"
	if ((s=getenv("$var")))
		addenv("$var", s);
EOF
	}
	if ($config{rcs} eq "svn" && $config{notify}) {
		# Support running directly as hooks/post-commit by passing
		# $2 in REV in the environment.
		$envsave.=<<"EOF"
	if (argc == 3)
		addenv("REV", argv[2]);
	else if ((s=getenv("REV")))
		addenv("REV", s);
EOF
	}
	if ($config{rcs} eq "tla" && $config{notify}) {
		$envsave.=<<"EOF"
	if ((s=getenv("ARCH_VERSION")))
		addenv("ARCH_VERSION", s);
EOF
	}
	
	$Data::Dumper::Indent=0; # no newlines
	my $configstring=Data::Dumper->Dump([\%config], ['*config']);
	$configstring=~s/\\/\\\\/g;
	$configstring=~s/"/\\"/g;
	$configstring=~s/\n/\\n/g;
	
	#translators: The first parameter is a filename, and the second is
	#translators: a (probably not translated) error message.
	open(OUT, ">$wrapper.c") || error(sprintf(gettext("failed to write %s: %s"), "$wrapper.c", $!));;
	print OUT <<"EOF";
/* A wrapper for ikiwiki, can be safely made suid. */
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

extern char **environ;
char *newenviron[$#envsave+5];
int i=0;

addenv(char *var, char *val) {
	char *s=malloc(strlen(var)+1+strlen(val)+1);
	if (!s)
		perror("malloc");
	sprintf(s, "%s=%s", var, val);
	newenviron[i++]=s;
}

int main (int argc, char **argv) {
	/* Sanitize environment. */
	char *s;
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
} #}}}

1
