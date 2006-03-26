#!/usr/bin/perl

use warnings;
use strict;
use Cwd q{abs_path};
use Data::Dumper;

package IkiWiki;

sub gen_wrapper () { #{{{
	$config{srcdir}=abs_path($config{srcdir});
	$config{destdir}=abs_path($config{destdir});
	my $this=abs_path($0);
	if (! -x $this) {
		error("$this doesn't seem to be executable");
	}

	if ($config{setup}) {
		error("cannot create a wrapper that uses a setup file");
	}
	my $wrapper=possibly_foolish_untaint($config{wrapper});
	delete $config{wrapper};
	
	my @envsave;
	push @envsave, qw{REMOTE_ADDR QUERY_STRING REQUEST_METHOD REQUEST_URI
	               CONTENT_TYPE CONTENT_LENGTH GATEWAY_INTERFACE
		       HTTP_COOKIE} if $config{cgi};
	my $envsave="";
	foreach my $var (@envsave) {
		$envsave.=<<"EOF"
	if ((s=getenv("$var")))
		asprintf(&newenviron[i++], "%s=%s", "$var", s);
EOF
	}
	
	$Data::Dumper::Indent=0; # no newlines
	my $configstring=Data::Dumper->Dump([\%config], ['*config']);
	$configstring=~s/\\/\\\\/g;
	$configstring=~s/"/\\"/g;
	
	open(OUT, ">$wrapper.c") || error("failed to write $wrapper.c: $!");;
	print OUT <<"EOF";
/* A wrapper for ikiwiki, can be safely made suid. */
#define _GNU_SOURCE
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

extern char **environ;

int main (int argc, char **argv) {
	/* Sanitize environment. */
	char *s;
	char *newenviron[$#envsave+4];
	int i=0;
$envsave
	newenviron[i++]="HOME=$ENV{HOME}";
	newenviron[i++]="WRAPPED_OPTIONS=$configstring";
	newenviron[i]=NULL;
	environ=newenviron;

	execl("$this", "$this", NULL);
	perror("failed to run $this");
	exit(1);
}
EOF
	close OUT;
	if (system("gcc", "$wrapper.c", "-o", $wrapper) != 0) {
		error("failed to compile $wrapper.c");
	}
	unlink("$wrapper.c");
	if (defined $config{wrappermode} &&
	    ! chmod(oct($config{wrappermode}), $wrapper)) {
		error("chmod $wrapper: $!");
	}
	print "successfully generated $wrapper\n";
} #}}}

1
