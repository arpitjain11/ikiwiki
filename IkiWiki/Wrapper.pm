#!/usr/bin/perl

use warnings;
use strict;

package IkiWiki;

sub gen_wrapper () { #{{{
	eval q{use Cwd 'abs_path'};
	$config{srcdir}=abs_path($config{srcdir});
	$config{destdir}=abs_path($config{destdir});
	my $this=abs_path($0);
	if (! -x $this) {
		error("$this doesn't seem to be executable");
	}

	if ($config{setup}) {
		error("cannot create a wrapper that uses a setup file");
	}
	
	my @params=($config{srcdir}, $config{destdir},
		"--wikiname=$config{wikiname}",
		"--templatedir=$config{templatedir}");
	push @params, "--verbose" if $config{verbose};
	push @params, "--rebuild" if $config{rebuild};
	push @params, "--nosvn" if !$config{svn};
	push @params, "--cgi" if $config{cgi};
	push @params, "--url=$config{url}" if length $config{url};
	push @params, "--cgiurl=$config{cgiurl}" if length $config{cgiurl};
	push @params, "--historyurl=$config{historyurl}" if length $config{historyurl};
	push @params, "--diffurl=$config{diffurl}" if length $config{diffurl};
	push @params, "--anonok" if $config{anonok};
	push @params, "--adminuser=$_" foreach @{$config{adminuser}};
	my $params=join(" ", @params);
	my $call='';
	foreach my $p ($this, $this, @params) {
		$call.=qq{"$p", };
	}
	$call.="NULL";
	
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
	
	open(OUT, ">ikiwiki-wrap.c") || error("failed to write ikiwiki-wrap.c: $!");;
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
	char *newenviron[$#envsave+3];
	int i=0;
$envsave
	newenviron[i++]="HOME=$ENV{HOME}";
	newenviron[i]=NULL;
	environ=newenviron;

	if (argc == 2 && strcmp(argv[1], "--params") == 0) {
		printf("$params\\n");
		exit(0);
	}
	
	execl($call);
	perror("failed to run $this");
	exit(1);
}
EOF
	close OUT;
	if (system("gcc", "ikiwiki-wrap.c", "-o", possibly_foolish_untaint($config{wrapper})) != 0) {
		error("failed to compile ikiwiki-wrap.c");
	}
	unlink("ikiwiki-wrap.c");
	if (defined $config{wrappermode} &&
	    ! chmod(oct($config{wrappermode}), possibly_foolish_untaint($config{wrapper}))) {
		error("chmod $config{wrapper}: $!");
	}
	print "successfully generated $config{wrapper}\n";
} #}}}

1
