#!/usr/bin/perl

package IkiWiki;

use warnings;
use strict;
use IkiWiki;
use Encode;
use open qw{:utf8 :std};

sub bzr_log ($) { #{{{
	my $out = shift;
	my @infos = ();
	my $key = undef;

	while (<$out>) {
		my $line = $_;
		my ($value);
		if ($line =~ /^message:/) {
			$key = "message";
			$infos[$#infos]{$key} = "";
		}
		elsif ($line =~ /^(modified|added|renamed|renamed and modified|removed):/) {
			$key = "files";
			unless (defined($infos[$#infos]{$key})) { $infos[$#infos]{$key} = ""; }
		}
		elsif (defined($key) and $line =~ /^  (.*)/) {
			$infos[$#infos]{$key} .= $1;
		}
		elsif ($line eq "------------------------------------------------------------\n") {
			$key = undef;
			push (@infos, {});
		}
		else {
			chomp $line;
				($key, $value) = split /: +/, $line, 2;
			$infos[$#infos]{$key} = $value;
		} 
	}
	close $out;

	return @infos;
} #}}}

sub rcs_update () { #{{{
	my @cmdline = ("bzr", "update", "--quiet", $config{srcdir});
	if (system(@cmdline) != 0) {
		warn "'@cmdline' failed: $!";
	}
} #}}}

sub rcs_prepedit ($) { #{{{
	return "";
} #}}}

sub rcs_commit ($$$;$$) { #{{{
	my ($file, $message, $rcstoken, $user, $ipaddr) = @_;

	if (defined $user) {
		$user = possibly_foolish_untaint($user);
	}
	elsif (defined $ipaddr) {
		$user = "Anonymous from ".possibly_foolish_untaint($ipaddr);
	}
	else {
		$user = "Anonymous";
	}

	$message = possibly_foolish_untaint($message);
	if (! length $message) {
		$message = "no message given";
	}

	my @cmdline = ("bzr", "commit", "--quiet", "-m", $message, "--author", $user,
	               $config{srcdir}."/".$file);
	if (system(@cmdline) != 0) {
		warn "'@cmdline' failed: $!";
	}

	return undef; # success
} #}}}

sub rcs_commit_staged ($$$) {
	# Commits all staged changes. Changes can be staged using rcs_add,
	# rcs_remove, and rcs_rename.
	my ($message, $user, $ipaddr)=@_;
	
	error("rcs_commit_staged not implemented for bzr"); # TODO
}

sub rcs_add ($) { # {{{
	my ($file) = @_;

	my @cmdline = ("bzr", "add", "--quiet", "$config{srcdir}/$file");
	if (system(@cmdline) != 0) {
		warn "'@cmdline' failed: $!";
	}
} #}}}

sub rcs_remove ($) { # {{{
	my ($file) = @_;

	error("rcs_remove not implemented for bzr"); # TODO
} #}}}

sub rcs_rename ($$) { # {{{
	my ($src, $dest) = @_;

	error("rcs_rename not implemented for bzr"); # TODO
} #}}}

sub rcs_recentchanges ($) { #{{{
	my ($num) = @_;

	my @cmdline = ("bzr", "log", "-v", "--show-ids", "--limit", $num, 
		           $config{srcdir});
	open (my $out, "@cmdline |");

	eval q{use Date::Parse};
	error($@) if $@;

	my @ret;
	foreach my $info (bzr_log($out)) {
		my @pages = ();
		my @message = ();
        
		foreach my $msgline (split(/\n/, $info->{message})) {
			push @message, { line => $msgline };
		}

		foreach my $file (split(/\n/, $info->{files})) {
			my ($filename, $fileid) = split(/[ \t]+/, $file);
			my $diffurl = $config{'diffurl'};
			$diffurl =~ s/\[\[file\]\]/$filename/go;
			$diffurl =~ s/\[\[file-id\]\]/$fileid/go;
			$diffurl =~ s/\[\[r2\]\]/$info->{revno}/go;

			push @pages, {
				page => pagename($filename),
				diffurl => $diffurl,
			};
		}

		my $user = $info->{"committer"};
		if (defined($info->{"author"})) { $user = $info->{"author"}; }
		$user =~ s/\s*<.*>\s*$//;
		$user =~ s/^\s*//;

		push @ret, {
			rev        => $info->{"revno"},
			user       => $user,
			committype => "bzr",
			when       => time - str2time($info->{"timestamp"}),
			message    => [@message],
			pages      => [@pages],
		};
	}

	return @ret;
} #}}}

sub rcs_getctime ($) { #{{{
	my ($file) = @_;

	# XXX filename passes through the shell here, should try to avoid
	# that just in case
	my @cmdline = ("bzr", "log", "--limit", '1', "$config{srcdir}/$file");
	open (my $out, "@cmdline |");

	my @log = bzr_log($out);

	if (length @log < 1) {
		return 0;
	}

	eval q{use Date::Parse};
	error($@) if $@;
	
	my $ctime = str2time($log[0]->{"timestamp"});
	return $ctime;
} #}}}

1
