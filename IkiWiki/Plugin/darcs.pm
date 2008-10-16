# Support for the darcs rcs, <URL:http://darcs.net/>.
# Copyright (C) 2006  Thomas Schwinge <tschwinge@gnu.org>
#               2007  Benjamin A'Lee <bma@bmalee.eu>
#                     Tuomo Valkonen <tuomov@iki.fi>
#               2008  Simon Michael <simon@joyful.com>
#                     Petr Ročkai <me@mornfall.net>
#                     Sven M. Hallberg <pesco@khjk.org>
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2 of the License, or (at your
# option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

# History (see http://ikiwiki.info/todo/darcs/):
#
#  * Thomas Schwinge wrote the original file, implementing only rcs_commit.
#  * Benjamin A'Lee contributed an alternative implementation.
#  * Tuomo Valkonen contributed rcs_getctime and stub rcs_recentchanges.
#  * Simon Michael contributed multiple changes.
#  * Petr Ročkai fixed rcs_recentchanges and added caching to rcs_getctime.
#  * Sven M. Hallberg merged the above and added missing features.


# We're guaranteed to be the only instance of ikiwiki running at a given
# time.  It is essential that only ikiwiki is working on a particular
# repository.  That means one instance of ikiwiki and it also means that
# you must not 'darcs push' into this repository, as this might create
# race conditions, as I understand it.


package IkiWiki::Plugin::darcs;

use warnings;
use strict;
use IkiWiki;


sub import {
	hook(type => "checkconfig", id => "darcs", call => \&checkconfig);
	hook(type => "getsetup", id => "darcs", call => \&getsetup);
	hook(type => "rcs", id => "rcs_update", call => \&rcs_update);
	hook(type => "rcs", id => "rcs_prepedit", call => \&rcs_prepedit);
	hook(type => "rcs", id => "rcs_commit", call => \&rcs_commit);
	hook(type => "rcs", id => "rcs_commit_staged", call => \&rcs_commit_staged);
	hook(type => "rcs", id => "rcs_add", call => \&rcs_add);
	hook(type => "rcs", id => "rcs_remove", call => \&rcs_remove);
	hook(type => "rcs", id => "rcs_rename", call => \&rcs_rename);
	hook(type => "rcs", id => "rcs_recentchanges", call => \&rcs_recentchanges);
	hook(type => "rcs", id => "rcs_diff", call => \&rcs_diff);
	hook(type => "rcs", id => "rcs_getctime", call => \&rcs_getctime);
}


# Internal functions

sub silentsystem (@) {
	open(SAVED_STDOUT, ">&STDOUT");
	open(STDOUT, ">/dev/null");
	my $ret = system @_;
	open(STDOUT, ">&SAVED_STDOUT");
	return $ret;
}

sub darcs_info ($$$) {
	my $field = shift;
	my $repodir = shift;
	my $file = shift; # Relative to the repodir.

	my $child = open(DARCS_CHANGES, "-|");
	if (! $child) {
		exec('darcs', 'changes', '--repodir', $repodir, '--xml-output', $file) or
			error("failed to run 'darcs changes'");
	}

	# Brute force for now.  :-/
	while (<DARCS_CHANGES>) {
		last if /^<\/created_as>$/;
	}
	($_) = <DARCS_CHANGES> =~ /$field=\'([^\']+)/;
	$field eq 'hash' and s/\.gz//; # Strip away the '.gz' from 'hash'es.

	close(DARCS_CHANGES);

	return $_;
}

sub file_in_vc($$) {
    my $repodir = shift;
    my $file = shift;

	my $child = open(DARCS_MANIFEST, "-|");
	if (! $child) {
		exec('darcs', 'query', 'manifest', '--repodir', $repodir) or
			error("failed to run 'darcs query manifest'");
	}
	my $found=0;
	while (<DARCS_MANIFEST>) {
		$found = 1, last if /^(\.\/)?$file$/;
	}
	close(DARCS_MANIFEST) or error("'darcs query manifest' exited " . $?);

	return $found;
}

sub darcs_rev($) {
	my $file = shift; # Relative to the repodir.
	my $repodir = $config{srcdir};

    return "" if (! file_in_vc($repodir, $file));
	my $hash = darcs_info('hash', $repodir, $file);
	return defined $hash ? $hash : "";
}


# Exported functions.

sub checkconfig() {
	if (defined $config{darcs_wrapper} && length $config{darcs_wrapper}) {
		push @{$config{wrappers}}, {
			wrapper => $config{darcs_wrapper},
			wrappermode => (defined $config{darcs_wrappermode} ? $config{darcs_wrappermode} : "06755"),
		};
	}
}

sub getsetup() {
	return
	plugin => {
		safe => 0, # rcs plugin
		rebuild => undef,
	},
	darcs_wrapper => {
		type => "string",
		example => "/darcs/repo/_darcs/ikiwiki-wrapper",
		description => "wrapper to generate (set as master repo apply hook)",
		safe => 0, # file
		rebuild => 0,
	},
	darcs_wrappermode => {
		type => "string",
		example => '06755',
		description => "mode for darcs_wrapper (can safely be made suid)",
		safe => 0,
		rebuild => 0,
	},
	historyurl => {
		type => "string",
		example => "http://darcs.example.com/darcsweb.cgi?r=wiki;a=filehistory;f=[[file]]",
		description => "darcsweb url to show file history ([[file]] substituted)",
		safe => 1,
		rebuild => 1,
	},
	diffurl => {
		type => "string",
		example => "http://darcs.example.com/darcsweb.cgi?r=wiki;a=filediff;h=[[hash]];f=[[file]]",
		description => "darcsweb url to show a diff ([[hash]] and [[file]] substituted)",
		safe => 1,
		rebuild => 1,
	},
}

sub rcs_update () {
	silentsystem('darcs', "pull", "--repodir", $config{srcdir}, "-qa")
}

sub rcs_prepedit ($) {
	# Prepares to edit a file under revision control.  Returns a token that
	# must be passed to rcs_commit() when the file is to be commited.  For us,
	# this token the hash value of the latest patch that modifies the file,
	# i.e. something like its current revision.  If the file is not yet added
	# to the repository, we return TODO: the empty string.

	my $file = shift; # Relative to the repodir.
	my $rev = darcs_rev($file);
	return $rev;
}

sub rcs_commit ($$$;$$) {
	# Commit the page.  Returns 'undef' on success and a version of the page
	# with conflict markers on failure.

	my ($file, $message, $rcstoken, $user, $ipaddr) = @_;

	# Compute if the "revision" of $file changed.
	my $changed = darcs_rev($file) ne $rcstoken;

	# Yes, the following is a bit convoluted.
	if ($changed) {
	# TODO.  Invent a better, non-conflicting name.
	rename("$config{srcdir}/$file", "$config{srcdir}/$file.save") or
		error("failed to rename $file to $file.save: $!");

	# Roll the repository back to $rcstoken.

	# TODO.  Can we be sure that no changes are lost?  I think that
	# we can, if we make sure that the 'darcs push' below will always
	# succeed.

	# We need to revert everything as 'darcs obliterate' might choke
	# otherwise.
	# TODO: 'yes | ...' needed?  Doesn't seem so.
	silentsystem('darcs', "revert", "--repodir", $config{srcdir}, "--all") and
		error("'darcs revert' failed");
	# Remove all patches starting at $rcstoken.
	my $child = open(DARCS_OBLITERATE, "|-");
	if (! $child) {
		open(STDOUT, ">/dev/null");
		exec('darcs', "obliterate", "--repodir", $config{srcdir},
		   "--match", "hash " . $rcstoken) and
		   error("'darcs obliterate' failed");
	}
	while (print DARCS_OBLITERATE "y") {
		;
	}
	close(DARCS_OBLITERATE);
	# Restore the $rcstoken one.
	silentsystem('darcs', "pull", "--quiet", "--repodir", $config{srcdir},
		"--match", "hash " . $rcstoken, "--all") and
		error("'darcs pull' failed");

	# We're back at $rcstoken.  Re-install the modified file.
	rename("$config{srcdir}/$file.save", "$config{srcdir}/$file") or
		error("failed to rename $file.save to $file: $!");
	}

	# Record the changes.
	my $author;
	if (defined $user) {
		$author = "$user\@web";
	} elsif (defined $ipaddr) {
		$author = "$ipaddr\@web";
	} else {
		$author = "anon\@web";
	}
	if (!defined $message || !length($message)) {
		$message = "empty message";
	}
	silentsystem('darcs', 'record', '--repodir', $config{srcdir}, '--all',
	   '-m', $message, '--author', $author, $file) and
		error("'darcs record' failed");

	# Update the repository by pulling from the default repository, which is
	# master repository.
	silentsystem('darcs', "pull", "--quiet", "--repodir", $config{srcdir},
		"--all") and error("'darcs pull' failed");

	# If this updating yields any conflicts, we'll record them now to resolve
	# them.  If nothing is recorded, there are no conflicts.
	$rcstoken = darcs_rev($file);
	# TODO: Use only the first line here, i.e. only the patch name?
	writefile("$file.log", $config{srcdir}, 'resolve conflicts: ' . $message);
	silentsystem('darcs', 'record', '--repodir', $config{srcdir}, '--all',
		'-m', 'resolve conflicts: ' . $message, '--author', $author, $file) and
		error("'darcs record' failed");
	my $conflicts = darcs_rev($file) ne $rcstoken;
	unlink("$config{srcdir}/$file.log") or
	error("failed to remove '$file.log'");

	# Push the changes to the main repository.
	silentsystem('darcs', 'push', '--quiet', '--repodir', $config{srcdir}, '--all')
	and error("'darcs push' failed");
	# TODO: darcs send?

	if ($conflicts) {
		my $document = readfile("$config{srcdir}/$file");
		# Try to leave everything in a consistent state.
		# TODO: 'yes | ...' needed?  Doesn't seem so.
		silentsystem('darcs', "revert", "--repodir", $config{srcdir}, "--all") and
			warn("'darcs revert' failed");
		return $document;
	} else {
		return undef;
	}
}

sub rcs_commit_staged($$$) {
	my ($message, $user, $ipaddr) = @_;

	my $author;
	if (defined $user) {
		$author = "$user\@web";
	} elsif (defined $ipaddr) {
		$author = "$ipaddr\@web";
	} else {
		$author = "anon\@web";
	}
	if (!defined $message || !length($message)) {
		$message = "empty message";
	}

	silentsystem('darcs', "record", "--repodir", $config{srcdir}, "-a", "-A", $author,
		"-m", $message)	and error("'darcs record' failed");

	# Push the changes to the main repository.
	silentsystem('darcs', 'push', '--quiet', '--repodir', $config{srcdir}, '--all')
		and error("'darcs push' failed");
	# TODO: darcs send?

	return undef;
}

sub rcs_add ($) {
	my $file = shift; # Relative to the repodir.

	if(! file_in_vc($config{srcdir}, $file)) {
		# Intermediate directories will be added automagically.
		system('darcs', 'add', '--quiet', '--repodir', $config{srcdir},
			'--boring', $file) and error("'darcs add' failed");
	}
}

sub rcs_remove ($) {
	my $file = shift; # Relative to the repodir.

	unlink($config{srcdir}.'/'.$file);
}

sub rcs_rename ($$) {
	my $a = shift; # Relative to the repodir.
	my $b = shift; # Relative to the repodir.

	system('darcs', 'mv', '--repodir', $config{srcdir}, $a, $b)
	   and error("'darcs mv' failed");
}

sub rcs_recentchanges ($) {
	my $num=shift;
	my @ret;

	eval q{use Date::Parse};
	eval q{use XML::Simple};

	my $repodir=$config{srcdir};

	debug("darcs recent changes: $num");

	my $child = open(LOG, "-|");
	if (! $child) {
		$ENV{"DARCS_DONT_ESCAPE_ANYTHING"}=1;
		exec("darcs", "changes", "--xml", 
			"--summary",
			 "--repodir", "$repodir",
			 "--last", "$num")
		|| error("'darcs changes' failed to run");
	}
	my $data;
	$data .= $_ while(<LOG>);
	close LOG;

	my $log = XMLin($data, ForceArray => 1);

	debug("parsing recent changes...");
	foreach my $patch (@{$log->{patch}}) {
		my $date=$patch->{local_date};
		my $hash=$patch->{hash};
		my $when=str2time($date);
		my (@pages, @files, @pg);
		push @pages, $_ for (@{$patch->{summary}->[0]->{modify_file}});
		push @pages, $_ for (@{$patch->{summary}->[0]->{add_file}});
		push @pages, $_ for (@{$patch->{summary}->[0]->{remove_file}});
		for (@pages) {
			my $f = $_;
			$f = $_->{content} if (ref $_);
			$f =~ s,^\s+,,; $f =~ s,\s+$,,; # cut whitespace

			push @files, $f;
		}
		for (@{$patch->{summary}->[0]->{move}}) {
			my $p = $_;
			push @files, $p->{from};
		}

		for (@files) {
			my $f = $_;
			my $d = defined $config{'diffurl'} ? $config{'diffurl'} : "";
			$d =~ s/\[\[file\]\]/$f/go;
			$d =~ s/\[\[hash\]\]/$hash/go;

			debug("file: $f");
			debug("diffurl: $d");
			push @pg, {
				page => pagename($f),
				diffurl => $d,
			};
		}
		next unless (scalar @pg > 0);
		debug("recent change: " . $patch->{name}[0] . " ("
			. scalar @pg . " changes)");

		my @message;
		push @message, { line => $_ } for (@{$patch->{name}});

		my $committype;
		if ($patch->{author} =~ /\@web$/) {
			$committype = "web";
		} else {
			$committype = "darcs";
		}

		push @ret, {
			rev => $patch->{hash},
			user => $patch->{author},
			committype => $committype,
			when => $when, 
			message => [@message],
			pages => [@pg],
		};
	}

	return @ret;
}

sub rcs_diff ($) {
	my $rev=shift;
	my @lines;
	foreach my $line (silentsystem("darcs", "diff", "--match", "hash ".$rev)) {
		if (@lines || $line=~/^diff/) {
			push @lines, $line."\n";
		}
	}
	if (wantarray) {
		return @lines;
	}
	else {
		return join("", @lines);
	}
}

sub rcs_getctime ($) {
	my $file=shift;

	eval q{use Date::Parse};
	eval q{use XML::Simple};
	local $/=undef;

	# Sigh... doing things the hard way again
	my $repodir=$config{srcdir};

	my $filer=substr($file, length($repodir));
	$filer =~ s:^[/]+::;

	my $child = open(LOG, "-|");
	if (! $child) {
		exec("darcs", "changes", "--xml", "--reverse",
			"--repodir", "$repodir", "$filer")
		|| error("'darcs changes $filer' failed to run");
	}

	my $data;
	$data .= $_ while(<LOG>);
	close LOG;

	my $log = XMLin($data, ForceArray => 1);

	my $datestr=$log->{patch}[0]->{local_date};

	if (! defined $datestr) {
		warn "failed to get ctime for $filer";
		return 0;
	}

	my $date=str2time($datestr);

	#debug("found ctime ".localtime($date)." for $filer");

	return $date;
}

1

# vim: ts=4 sw=4 noet
