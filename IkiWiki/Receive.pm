#!/usr/bin/perl

package IkiWiki::Receive;

use warnings;
use strict;
use IkiWiki;

sub getuser () { #{{{
	my $user=(getpwuid($<))[0];
	if (! defined $user) {
		error("cannot determine username for $<");
	}
	return $user;
} #}}}

sub trusted () { #{{{
	my $user=getuser();
	return ! ref $config{untrusted_committers} ||
		! grep { $_ eq $user } @{$config{untrusted_committers}};
} #}}}

sub test () { #{{{
	exit 0 if trusted();
	IkiWiki::rcs_test_receive();
	
	# Dummy up a cgi environment to use when calling check_canedit
	# and friends.
	eval q{use CGI};
	error($@) if $@;
	my $cgi=CGI->new;
	require IkiWiki::CGI;
	my $session=IkiWiki::cgi_getsession($cgi);
	my $user=getuser();
	$session->param("name", $user);
	$ENV{REMOTE_ADDR}='unknown' unless exists $ENV{REMOTE_ADDR};

	lockwiki();
	loadindex();

	my %newfiles;

	foreach my $change (IkiWiki::rcs_receive()) {
		# This untaint is safe because we check file_pruned and
		# wiki_file_regexp.
		my $file=$change->{file}=~/$config{wiki_file_regexp}/;
		$file=possibly_foolish_untaint($file);
		if (! defined $file || ! length $file ||
		    IkiWiki::file_pruned($file, $config{srcdir})) {
			error(gettext("bad file name"));
		}

		my $type=pagetype($file);
		my $page=pagename($file) if defined $type;
		
		if ($change->{action} eq 'add') {
			$newfiles{$file}=1;
		}

		if ($change->{action} eq 'change' ||
		    $change->{action} eq 'add') {
			if (defined $page) {
				if (IkiWiki->can("check_canedit") &&
				    IkiWiki::check_canedit($page, $cgi, $session)) {
				    	next;
				}
			}
			else {
				# TODO
				#if (IkiWiki::Plugin::attachment->can("check_canattach") &&
				#    IkiWiki::Plugin::attachment::check_canattach($session, $file, $path)) {
				#    	next;
				#}
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

			if (IkiWiki::Plugin::remove->can("check_canremove") &&
			    IkiWiki::Plugin::remove::check_canremove(defined $page ? $page : $file, $cgi, $session)) {
				next;
			}
		}
		else {
			error "unknown action ".$change->{action};
		}
				
		error sprintf(gettext("you are not allowed to change %s"), $file);
	}

	exit 0;
} #}}}

1
