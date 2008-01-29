#!/usr/bin/perl

use warnings;
use strict;
use IkiWiki;
use Encode;
use open qw{:utf8 :std};

package IkiWiki;

sub mercurial_log($) {
	my $out = shift;
	my @infos;

	while (<$out>) {
		my $line = $_;
		my ($key, $value);

		if (/^description:/) {
			$key = "description";
			$value = "";

			# slurp everything as the description text 
			# until the next changeset
			while (<$out>) {
				if (/^changeset: /) {
					$line = $_;
					last;
				}

				$value .= $_;
			}

			local $/ = "";
			chomp $value;
			$infos[$#infos]{$key} = $value;
		}

		chomp $line;
	        ($key, $value) = split /: +/, $line, 2;

		if ($key eq "changeset") {
			push @infos, {};

			# remove the revision index, which is strictly 
			# local to the repository
			$value =~ s/^\d+://;
		}

		$infos[$#infos]{$key} = $value;
	}
	close $out;

	return @infos;
}

sub rcs_update () { #{{{
	my @cmdline = ("hg", "-q", "-R", "$config{srcdir}", "update");
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

	my @cmdline = ("hg", "-q", "-R", $config{srcdir}, "commit", 
	               "-m", $message, "-u", $user);
	if (system(@cmdline) != 0) {
		warn "'@cmdline' failed: $!";
	}

	return undef; # success
} #}}}

sub rcs_add ($) { # {{{
	my ($file) = @_;

	my @cmdline = ("hg", "-q", "-R", "$config{srcdir}", "add", "$config{srcdir}/$file");
	if (system(@cmdline) != 0) {
		warn "'@cmdline' failed: $!";
	}
} #}}}

sub rcs_recentchanges ($) { #{{{
	my ($num) = @_;

	eval q{use CGI 'escapeHTML'};
	error($@) if $@;

	my @cmdline = ("hg", "-R", $config{srcdir}, "log", "-v", "-l", $num,
		"--style", "default");
	open (my $out, "@cmdline |");

	eval q{use Date::Parse};
	error($@) if $@;

	my @ret;
	foreach my $info (mercurial_log($out)) {
		my @pages = ();
		my @message = ();
        
		foreach my $msgline (split(/\n/, $info->{description})) {
			push @message, { line => $msgline };
		}

		foreach my $file (split / /,$info->{files}) {
			my $diffurl = $config{'diffurl'};
			$diffurl =~ s/\[\[file\]\]/$file/go;
			$diffurl =~ s/\[\[r2\]\]/$info->{changeset}/go;

			push @pages, {
				page => pagename($file),
				diffurl => $diffurl,
			};
		}

		my $user = $info->{"user"};
		$user =~ s/\s*<.*>\s*$//;
		$user =~ s/^\s*//;

		push @ret, {
			rev        => $info->{"changeset"},
			user       => $user,
			committype => "mercurial",
			when       => str2time($info->{"date"}),
			message    => [@message],
			pages      => [@pages],
		};
	}

	return @ret;
} #}}}

sub rcs_notify () { #{{{
	# TODO
} #}}}

sub rcs_getctime ($) { #{{{
	my ($file) = @_;

	# XXX filename passes through the shell here, should try to avoid
	# that just in case
	my @cmdline = ("hg", "-R", $config{srcdir}, "log", "-v", "-l", '1', 
		"--style", "default", "$config{srcdir}/$file");
	open (my $out, "@cmdline |");

	my @log = mercurial_log($out);

	if (length @log < 1) {
		return 0;
	}

	eval q{use Date::Parse};
	error($@) if $@;
	
	my $ctime = str2time($log[0]->{"date"});
	return $ctime;
} #}}}

1
