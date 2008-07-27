#!/usr/bin/perl

package IkiWiki;

use warnings;
use strict;
use IkiWiki;
use Encode;
use open qw{:utf8 :std};

hook(type => "checkconfig", id => "mercurial", call => sub { #{{{
	if (! defined $config{diffurl}) {
		$config{diffurl}="";
	}
	if (length $config{mercurial_wrapper}) {
		push @{$config{wrappers}}, {
			wrapper => $config{mercurial_wrapper},
			wrappermode => (defined $config{mercurial_wrappermode} ? $config{mercurial_wrappermode} : "06755"),
		};
	}
}); #}}}

hook(type => "getsetup", id => "mercurial", call => sub { #{{{
	return
		mercurial_wrapper => {
			type => "string",
			#example => # FIXME add example
			description => "mercurial post-commit executable to generate",
			safe => 0, # file
			rebuild => 0,
		},
		mercurial_wrappermode => {
			type => "string",
			example => '06755',
			description => "mode for mercurial_wrapper (can safely be made suid)",
			safe => 0,
			rebuild => 0,
		},
		historyurl => {
			type => "string",
			example => "http://example.com:8000/log/tip/[[file]]",
			description => "url to hg serve'd repository, to show file history ([[file]] substituted)",
			safe => 1,
			rebuild => 1,
		},
		diffurl => {
			type => "string",
			example => "http://localhost:8000/?fd=[[r2]];file=[[file]]",
			description => "url to hg serve'd repository, to show diff ([[file]] and [[r2]] substituted)",
			safe => 1,
			rebuild => 1,
		},
}); #}}}

sub mercurial_log ($) { #{{{
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
} #}}}

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

sub rcs_commit_staged ($$$) {
	# Commits all staged changes. Changes can be staged using rcs_add,
	# rcs_remove, and rcs_rename.
	my ($message, $user, $ipaddr)=@_;
	
	error("rcs_commit_staged not implemented for mercurial"); # TODO
}

sub rcs_add ($) { # {{{
	my ($file) = @_;

	my @cmdline = ("hg", "-q", "-R", "$config{srcdir}", "add", "$config{srcdir}/$file");
	if (system(@cmdline) != 0) {
		warn "'@cmdline' failed: $!";
	}
} #}}}

sub rcs_remove ($) { # {{{
	my ($file) = @_;

	error("rcs_remove not implemented for mercurial"); # TODO
} #}}}

sub rcs_rename ($$) { # {{{
	my ($src, $dest) = @_;

	error("rcs_rename not implemented for mercurial"); # TODO
} #}}}

sub rcs_recentchanges ($) { #{{{
	my ($num) = @_;

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

sub rcs_diff ($) { #{{{
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
