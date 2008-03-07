#!/usr/bin/perl

use warnings;
use strict;
use IkiWiki;
use Encode;
use open qw{:utf8 :std};

package IkiWiki;

my $sha1_pattern     = qr/[0-9a-fA-F]{40}/; # pattern to validate Git sha1sums
my $dummy_commit_msg = 'dummy commit';      # message to skip in recent changes

sub _safe_git (&@) { #{{{
	# Start a child process safely without resorting /bin/sh.
	# Return command output or success state (in scalar context).

	my ($error_handler, @cmdline) = @_;

	my $pid = open my $OUT, "-|";

	error("Cannot fork: $!") if !defined $pid;

	if (!$pid) {
		# In child.
		# Git commands want to be in wc.
		chdir $config{srcdir}
		    or error("Cannot chdir to $config{srcdir}: $!");
		exec @cmdline or error("Cannot exec '@cmdline': $!");
	}
	# In parent.

	my @lines;
	while (<$OUT>) {
		chomp;
		push @lines, $_;
	}

	close $OUT;

	$error_handler->("'@cmdline' failed: $!") if $? && $error_handler;

	return wantarray ? @lines : ($? == 0);
}
# Convenient wrappers.
sub run_or_die ($@) { _safe_git(\&error, @_) }
sub run_or_cry ($@) { _safe_git(sub { warn @_ },  @_) }
sub run_or_non ($@) { _safe_git(undef,            @_) }
#}}}

sub _merge_past ($$$) { #{{{
	# Unlike with Subversion, Git cannot make a 'svn merge -rN:M file'.
	# Git merge commands work with the committed changes, except in the
	# implicit case of '-m' of git checkout(1).  So we should invent a
	# kludge here.  In principle, we need to create a throw-away branch
	# in preparing for the merge itself.  Since branches are cheap (and
	# branching is fast), this shouldn't cost high.
	#
	# The main problem is the presence of _uncommitted_ local changes.  One
	# possible approach to get rid of this situation could be that we first
	# make a temporary commit in the master branch and later restore the
	# initial state (this is possible since Git has the ability to undo a
	# commit, i.e. 'git reset --soft HEAD^').  The method can be summarized
	# as follows:
	#
	# 	- create a diff of HEAD:current-sha1
	# 	- dummy commit
	# 	- create a dummy branch and switch to it
	# 	- rewind to past (reset --hard to the current-sha1)
	# 	- apply the diff and commit
	# 	- switch to master and do the merge with the dummy branch
	# 	- make a soft reset (undo the last commit of master)
	#
	# The above method has some drawbacks: (1) it needs a redundant commit
	# just to get rid of local changes, (2) somewhat slow because of the
	# required system forks.  Until someone points a more straight method
	# (which I would be grateful) I have implemented an alternative method.
	# In this approach, we hide all the modified files from Git by renaming
	# them (using the 'rename' builtin) and later restore those files in
	# the throw-away branch (that is, we put the files themselves instead
	# of applying a patch).

	my ($sha1, $file, $message) = @_;

	my @undo;      # undo stack for cleanup in case of an error
	my $conflict;  # file content with conflict markers

	eval {
		# Hide local changes from Git by renaming the modified file.
		# Relative paths must be converted to absolute for renaming.
		my ($target, $hidden) = (
		    "$config{srcdir}/${file}", "$config{srcdir}/${file}.${sha1}"
		);
		rename($target, $hidden)
		    or error("rename '$target' to '$hidden' failed: $!");
		# Ensure to restore the renamed file on error.
		push @undo, sub {
			return if ! -e "$hidden"; # already renamed
			rename($hidden, $target)
			    or warn "rename '$hidden' to '$target' failed: $!";
		};

		my $branch = "throw_away_${sha1}"; # supposed to be unique

		# Create a throw-away branch and rewind backward.
		push @undo, sub { run_or_cry('git', 'branch', '-D', $branch) };
		run_or_die('git', 'branch', $branch, $sha1);

		# Switch to throw-away branch for the merge operation.
		push @undo, sub {
			if (!run_or_cry('git', 'checkout', $config{gitmaster_branch})) {
				run_or_cry('git', 'checkout','-f',$config{gitmaster_branch});
			}
		};
		run_or_die('git', 'checkout', $branch);

		# Put the modified file in _this_ branch.
		rename($hidden, $target)
		    or error("rename '$hidden' to '$target' failed: $!");

		# _Silently_ commit all modifications in the current branch.
		run_or_non('git', 'commit', '-m', $message, '-a');
		# ... and re-switch to master.
		run_or_die('git', 'checkout', $config{gitmaster_branch});

		# Attempt to merge without complaining.
		if (!run_or_non('git', 'pull', '--no-commit', '.', $branch)) {
			$conflict = readfile($target);
			run_or_die('git', 'reset', '--hard');
		}
	};
	my $failure = $@;

	# Process undo stack (in reverse order).  By policy cleanup
	# actions should normally print a warning on failure.
	while (my $handle = pop @undo) {
		$handle->();
	}

	error("Git merge failed!\n$failure\n") if $failure;

	return $conflict;
} #}}}

sub _parse_diff_tree ($@) { #{{{
	# Parse the raw diff tree chunk and return the info hash.
	# See git-diff-tree(1) for the syntax.

	my ($prefix, $dt_ref) = @_;

	# End of stream?
	return if !defined @{ $dt_ref } ||
		  !defined @{ $dt_ref }[0] || !length @{ $dt_ref }[0];

	my %ci;
	# Header line.
	while (my $line = shift @{ $dt_ref }) {
		return if $line !~ m/^(.+) ($sha1_pattern)/;

		my $sha1 = $2;
		$ci{'sha1'} = $sha1;
		last;
	}

	# Identification lines for the commit.
	while (my $line = shift @{ $dt_ref }) {
		# Regexps are semi-stolen from gitweb.cgi.
		if ($line =~ m/^tree ([0-9a-fA-F]{40})$/) {
			$ci{'tree'} = $1;
		}
		elsif ($line =~ m/^parent ([0-9a-fA-F]{40})$/) {
			# XXX: collecting in reverse order
			push @{ $ci{'parents'} }, $1;
		}
		elsif ($line =~ m/^(author|committer) (.*) ([0-9]+) (.*)$/) {
			my ($who, $name, $epoch, $tz) =
			   ($1,   $2,    $3,     $4 );

			$ci{  $who          } = $name;
			$ci{ "${who}_epoch" } = $epoch;
			$ci{ "${who}_tz"    } = $tz;

			if ($name =~ m/^([^<]+) <([^@>]+)/) {
				my ($fullname, $username) = ($1, $2);
				$ci{"${who}_fullname"}    = $fullname;
				$ci{"${who}_username"}    = $username;
			}
			else {
				$ci{"${who}_fullname"} =
					$ci{"${who}_username"} = $name;
			}
		}
		elsif ($line =~ m/^$/) {
			# Trailing empty line signals next section.
			last;
		}
	}

	debug("No 'tree' seen in diff-tree output") if !defined $ci{'tree'};

	if (defined $ci{'parents'}) {
		$ci{'parent'} = @{ $ci{'parents'} }[0];
	}
	else {
		$ci{'parent'} = 0 x 40;
	}

	# Commit message.
	while (my $line = shift @{ $dt_ref }) {
		if ($line =~ m/^$/) {
			# Trailing empty line signals next section.
			last;
		};
		$line =~ s/^    //;
		push @{ $ci{'comment'} }, $line;
	}

	# Modified files.
	while (my $line = shift @{ $dt_ref }) {
		if ($line =~ m{^
			(:+)       # number of parents
			([^\t]+)\t # modes, sha1, status
			(.*)       # file names
		$}xo) {
			my $num_parents = length $1;
			my @tmp = split(" ", $2);
			my ($file, $file_to) = split("\t", $3);
			my @mode_from = splice(@tmp, 0, $num_parents);
			my $mode_to = shift(@tmp);
			my @sha1_from = splice(@tmp, 0, $num_parents);
			my $sha1_to = shift(@tmp);
			my $status = shift(@tmp);

			if ($file =~ m/^"(.*)"$/) {
				($file=$1) =~ s/\\([0-7]{1,3})/chr(oct($1))/eg;
			}
			$file =~ s/^\Q$prefix\E//;
			if (length $file) {
				push @{ $ci{'details'} }, {
					'file'      => decode_utf8($file),
					'sha1_from' => $sha1_from[0],
					'sha1_to'   => $sha1_to,
				};
			}
			next;
		};
		last;
	}

	return \%ci;
} #}}}

sub git_commit_info ($;$) { #{{{
	# Return an array of commit info hashes of num commits (default: 1)
	# starting from the given sha1sum.

	my ($sha1, $num) = @_;

	$num ||= 1;

	my @raw_lines = run_or_die('git', 'log', "--max-count=$num", 
		'--pretty=raw', '--raw', '--abbrev=40', '--always', '-c',
		'-r', $sha1, '--', '.');
	my ($prefix) = run_or_die('git', 'rev-parse', '--show-prefix');

	my @ci;
	while (my $parsed = _parse_diff_tree(($prefix or ""), \@raw_lines)) {
		push @ci, $parsed;
	}

	warn "Cannot parse commit info for '$sha1' commit" if !@ci;

	return wantarray ? @ci : $ci[0];
} #}}}

sub git_sha1 (;$) { #{{{
	# Return head sha1sum (of given file).

	my $file = shift || q{--};

	# Ignore error since a non-existing file might be given.
	my ($sha1) = run_or_non('git', 'rev-list', '--max-count=1', 'HEAD', $file);
	if ($sha1) {
		($sha1) = $sha1 =~ m/($sha1_pattern)/; # sha1 is untainted now
	} else { debug("Empty sha1sum for '$file'.") }
	return defined $sha1 ? $sha1 : q{};
} #}}}

sub rcs_update () { #{{{
	# Update working directory.

	if (length $config{gitorigin_branch}) {
		run_or_cry('git', 'pull', $config{gitorigin_branch});
	}
} #}}}

sub rcs_prepedit ($) { #{{{
	# Return the commit sha1sum of the file when editing begins.
	# This will be later used in rcs_commit if a merge is required.

	my ($file) = @_;

	return git_sha1($file);
} #}}}

sub rcs_commit ($$$;$$) { #{{{
	# Try to commit the page; returns undef on _success_ and
	# a version of the page with the rcs's conflict markers on
	# failure.

	my ($file, $message, $rcstoken, $user, $ipaddr) = @_;

	if (defined $user) {
		$message = "web commit by $user" .
		    (length $message ? ": $message" : "");
	}
	elsif (defined $ipaddr) {
		$message = "web commit from $ipaddr" .
		    (length $message ? ": $message" : "");
	}

	# Check to see if the page has been changed by someone else since
	# rcs_prepedit was called.
	my $cur    = git_sha1($file);
	my ($prev) = $rcstoken =~ /^($sha1_pattern)$/; # untaint

	if (defined $cur && defined $prev && $cur ne $prev) {
		my $conflict = _merge_past($prev, $file, $dummy_commit_msg);
		return $conflict if defined $conflict;
	}

	# git commit returns non-zero if file has not been really changed.
	# so we should ignore its exit status (hence run_or_non).
	$message = possibly_foolish_untaint($message);
	if (run_or_non('git', 'commit', '-q', '-m', $message, '-i', $file)) {
		if (length $config{gitorigin_branch}) {
			run_or_cry('git', 'push', $config{gitorigin_branch});
		}
	}

	return undef; # success
} #}}}

sub rcs_add ($) { # {{{
	# Add file to archive.

	my ($file) = @_;

	run_or_cry('git', 'add', $file);
} #}}}

sub rcs_recentchanges ($) { #{{{
	# List of recent changes.

	my ($num) = @_;

	eval q{use Date::Parse};
	error($@) if $@;

	my @rets;
	foreach my $ci (git_commit_info('HEAD', $num)) {
		# Skip redundant commits.
		next if (@{$ci->{'comment'}}[0] eq $dummy_commit_msg);

		my ($sha1, $when) = (
			$ci->{'sha1'},
			$ci->{'author_epoch'}
		);

		my (@pages, @messages);
		foreach my $detail (@{ $ci->{'details'} }) {
			my $file = $detail->{'file'};

			my $diffurl = $config{'diffurl'};
			$diffurl =~ s/\[\[file\]\]/$file/go;
			$diffurl =~ s/\[\[sha1_parent\]\]/$ci->{'parent'}/go;
			$diffurl =~ s/\[\[sha1_from\]\]/$detail->{'sha1_from'}/go;
			$diffurl =~ s/\[\[sha1_to\]\]/$detail->{'sha1_to'}/go;

			push @pages, {
				page => pagename($file),
				diffurl => $diffurl,
			};
		}
		push @messages, { line => $_ } foreach @{$ci->{'comment'}};

		my ($user, $type) = (q{}, "web");

		if (defined $messages[0] &&
		    $messages[0]->{line} =~ m/$config{web_commit_regexp}/) {
			$user = defined $2 ? "$2" : "$3";
			$messages[0]->{line} = $4;
		}
		else {
			$type ="git";
			$user = $ci->{'author_username'};
		}

		push @rets, {
			rev        => $sha1,
			user       => $user,
			committype => $type,
			when       => $when,
			message    => [@messages],
			pages      => [@pages],
		} if @pages;

		last if @rets >= $num;
	}

	return @rets;
} #}}}

sub rcs_diff ($) { #{{{
	my $rev=shift;
	my ($sha1) = $rev =~ /^($sha1_pattern)$/; # untaint
	return join("\n", run_or_non("git", "diff", "$sha1^", $sha1));
} #}}}

sub rcs_getctime ($) { #{{{
	my $file=shift;
	# Remove srcdir prefix
	$file =~ s/^\Q$config{srcdir}\E\/?//;

	my $sha1  = git_sha1($file);
	my $ci    = git_commit_info($sha1);
	my $ctime = $ci->{'author_epoch'};
	debug("ctime for '$file': ". localtime($ctime));

	return $ctime;
} #}}}

1
