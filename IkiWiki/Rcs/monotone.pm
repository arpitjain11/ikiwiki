#!/usr/bin/perl

package IkiWiki;

use warnings;
use strict;
use IkiWiki;
use Monotone;
use Date::Parse qw(str2time);
use Date::Format qw(time2str);

my $sha1_pattern = qr/[0-9a-fA-F]{40}/; # pattern to validate sha1sums

sub check_config() { #{{{
	if (!defined($config{mtnrootdir})) {
		$config{mtnrootdir} = $config{srcdir};
	}
	if (! -d "$config{mtnrootdir}/_MTN") {
		error("Ikiwiki srcdir does not seem to be a Monotone workspace (or set the mtnrootdir)!");
	}
	
	chdir $config{srcdir}
	    or error("Cannot chdir to $config{srcdir}: $!");

	my $child = open(MTN, "-|");
	if (! $child) {
		open STDERR, ">/dev/null";
		exec("mtn", "version") || error("mtn version failed to run");
	}

	my $version=undef;
	while (<MTN>) {
		if (/^monotone (\d+\.\d+) /) {
			$version=$1;
		}
	}

	close MTN || debug("mtn version exited $?");

	if (!defined($version)) {
		error("Cannot determine monotone version");
	}
	if ($version < 0.38) {
		error("Monotone version too old, is $version but required 0.38");
	}
} #}}}

sub get_rev () { #{{{
	my $sha1 = `mtn --root=$config{mtnrootdir} automate get_base_revision_id`;

	($sha1) = $sha1 =~ m/($sha1_pattern)/; # sha1 is untainted now
	if (! $sha1) {
		debug("Unable to get base revision for '$config{srcdir}'.")
	}

	return $sha1;
} #}}}

sub get_rev_auto ($) { #{{{
	my $automator=shift;

	my @results = $automator->call("get_base_revision_id");

	my $sha1 = $results[0];
	($sha1) = $sha1 =~ m/($sha1_pattern)/; # sha1 is untainted now
	if (! $sha1) {
		debug("Unable to get base revision for '$config{srcdir}'.")
	}

	return $sha1;
} #}}}

sub mtn_merge ($$$$) { #{{{
	my $leftRev=shift;
	my $rightRev=shift;
	my $branch=shift;
	my $author=shift;
    
	my $mergeRev;

	my $child = open(MTNMERGE, "-|");
	if (! $child) {
		open STDERR, ">&STDOUT";
		exec("mtn", "--root=$config{mtnrootdir}",
		     "explicit_merge", $leftRev, $rightRev,
		     $branch, "--author", $author, "--key", 
		     $config{mtnkey}) || error("mtn merge failed to run");
	}

	while (<MTNMERGE>) {
		if (/^mtn.\s.merged.\s($sha1_pattern)$/) {
			$mergeRev=$1;
		}
	}
	
	close MTNMERGE || return undef;

	debug("merged $leftRev, $rightRev to make $mergeRev");

	return $mergeRev;
} #}}}

sub commit_file_to_new_rev($$$$$$$$) { #{{{
	my $automator=shift;
	my $wsfilename=shift;
	my $oldFileID=shift;
	my $newFileContents=shift;
	my $oldrev=shift;
	my $branch=shift;
	my $author=shift;
	my $message=shift;
	
	#store the file
	my ($out, $err) = $automator->call("put_file", $oldFileID, $newFileContents);
	my ($newFileID) = ($out =~ m/^($sha1_pattern)$/);
	error("Failed to store file data for $wsfilename in repository")
		if (! defined $newFileID || length $newFileID != 40);

	# get the mtn filename rather than the workspace filename
	($out, $err) = $automator->call("get_corresponding_path", $oldrev, $wsfilename, $oldrev);
	my ($filename) = ($out =~ m/^file "(.*)"$/);
	error("Couldn't find monotone repository path for file $wsfilename") if (! $filename);
	debug("Converted ws filename of $wsfilename to repos filename of $filename");

	# then stick in a new revision for this file
	my $manifest = "format_version \"1\"\n\n".
	               "new_manifest [0000000000000000000000000000000000000000]\n\n".
	               "old_revision [$oldrev]\n\n".
	               "patch \"$filename\"\n".
	               " from [$oldFileID]\n".
	               "   to [$newFileID]\n";
	($out, $err) = $automator->call("put_revision", $manifest);
	my ($newRevID) = ($out =~ m/^($sha1_pattern)$/);
	error("Unable to make new monotone repository revision")
		if (! defined $newRevID || length $newRevID != 40);
	debug("put revision: $newRevID");
	
	# now we need to add certs for this revision...
	# author, branch, changelog, date
	$automator->call("cert", $newRevID, "author", $author);
	$automator->call("cert", $newRevID, "branch", $branch);
	$automator->call("cert", $newRevID, "changelog", $message);
	$automator->call("cert", $newRevID, "date",
		time2str("%Y-%m-%dT%T", time, "UTC"));
	
	debug("Added certs for rev: $newRevID");
	return $newRevID;
} #}}}

sub read_certs ($$) { #{{{
	my $automator=shift;
	my $rev=shift;
	my @results = $automator->call("certs", $rev);
	my @ret;

	my $line = $results[0];
	while ($line =~ m/\s+key\s"(.*?)"\nsignature\s"(ok|bad|unknown)"\n\s+name\s"(.*?)"\n\s+value\s"(.*?)"\n\s+trust\s"(trusted|untrusted)"\n/sg) {
		push @ret, {
			key => $1,
			signature => $2,
			name => $3,
			value => $4,
			trust => $5,
		};
	}

	return @ret;
} #}}}

sub get_changed_files ($$) { #{{{
	my $automator=shift;
	my $rev=shift;
	
	my @results = $automator->call("get_revision", $rev);
	my $changes=$results[0];

	my @ret;
	my %seen = ();
	
	while ($changes =~ m/\s*(add_file|patch|delete|rename)\s"(.*?)(?<!\\)"\n/sg) {
		my $file = $2;
		# don't add the same file multiple times
		if (! $seen{$file}) {
			push @ret, $file;
			$seen{$file} = 1;
		}
	}
	
	return @ret;
} #}}}

sub rcs_update () { #{{{
	check_config();

	if (defined($config{mtnsync}) && $config{mtnsync}) {
		if (system("mtn", "--root=$config{mtnrootdir}", "sync",
		           "--quiet", "--ticker=none", 
		           "--key", $config{mtnkey}) != 0) {
			debug("monotone sync failed before update");
		}
	}

	if (system("mtn", "--root=$config{mtnrootdir}", "update", "--quiet") != 0) {
		debug("monotone update failed");
	}
} #}}}

sub rcs_prepedit ($) { #{{{
	my $file=shift;

	check_config();

	# For monotone, return the revision of the file when
	# editing begins.
	return get_rev();
} #}}}

sub rcs_commit ($$$;$$) { #{{{
	# Tries to commit the page; returns undef on _success_ and
	# a version of the page with the rcs's conflict markers on failure.
	# The file is relative to the srcdir.
	my $file=shift;
	my $message=shift;
	my $rcstoken=shift;
	my $user=shift;
	my $ipaddr=shift;
	my $author;

	if (defined $user) {
		$author="Web user: " . $user;
	}
	elsif (defined $ipaddr) {
		$author="Web IP: " . $ipaddr;
	}
	else {
		$author="Web: Anonymous";
	}

	check_config();

	my ($oldrev)= $rcstoken=~ m/^($sha1_pattern)$/; # untaint
	my $rev = get_rev();
	if (defined $rev && defined $oldrev && $rev ne $oldrev) {
		my $automator = Monotone->new();
		$automator->open_args("--root", $config{mtnrootdir}, "--key", $config{mtnkey});

		# Something has been committed, has this file changed?
		my ($out, $err);
		$automator->setOpts("r", $oldrev, "r", $rev);
		($out, $err) = $automator->call("content_diff", $file);
		debug("Problem committing $file") if ($err ne "");
		my $diff = $out;
		
		if ($diff) {
			# Commit a revision with just this file changed off
			# the old revision.
			#
			# first get the contents
			debug("File changed: forming branch");
			my $newfile=readfile("$config{srcdir}/$file");
			
			# then get the old content ID from the diff
			if ($diff !~ m/^---\s$file\s+($sha1_pattern)$/m) {
				error("Unable to find previous file ID for $file");
			}
			my $oldFileID = $1;

			# get the branch we're working in
			($out, $err) = $automator->call("get_option", "branch");
			chomp $out;
			error("Illegal branch name in monotone workspace") if ($out !~ m/^([-\@\w\.]+)$/);
			my $branch = $1;

			# then put the new content into the DB (and record the new content ID)
			my $newRevID = commit_file_to_new_rev($automator, $file, $oldFileID, $newfile, $oldrev, $branch, $author, $message);

			$automator->close();

			# if we made it to here then the file has been committed... revert the local copy
			if (system("mtn", "--root=$config{mtnrootdir}", "revert", $file) != 0) {
				debug("Unable to revert $file after merge on conflicted commit!");
			}
			debug("Divergence created! Attempting auto-merge.");

			# see if it will merge cleanly
			$ENV{MTN_MERGE}="fail";
			my $mergeResult = mtn_merge($newRevID, $rev, $branch, $author);
			$ENV{MTN_MERGE}="";

			# push any changes so far
			if (defined($config{mtnsync}) && $config{mtnsync}) {
				if (system("mtn", "--root=$config{mtnrootdir}", "push", "--quiet", "--ticker=none", "--key", $config{mtnkey}) != 0) {
					debug("monotone push failed");
				}
			}
			
			if (defined($mergeResult)) {
				# everything is merged - bring outselves up to date
				if (system("mtn", "--root=$config{mtnrootdir}",
				           "update", "-r", $mergeResult) != 0) {
					debug("Unable to update to rev $mergeResult after merge on conflicted commit!");
				}
			}
			else {
				debug("Auto-merge failed.  Using diff-merge to add conflict markers.");
				
				$ENV{MTN_MERGE}="diffutils";
				$ENV{MTN_MERGE_DIFFUTILS}="partial=true";
				$mergeResult = mtn_merge($newRevID, $rev, $branch, $author);
				$ENV{MTN_MERGE}="";
				$ENV{MTN_MERGE_DIFFUTILS}="";
				
				if (!defined($mergeResult)) {
					debug("Unable to insert conflict markers!");
					error("Your commit succeeded. Unfortunately, someone else committed something to the same ".
				 		"part of the wiki at the same time. Both versions are stored in the monotone repository, ".
						"but at present the different versions cannot be reconciled through the web interface. ".
						"Please use the non-web interface to resolve the conflicts.");
				}
				
				if (system("mtn", "--root=$config{mtnrootdir}",
				           "update", "-r", $mergeResult) != 0) {
					debug("Unable to update to rev $mergeResult after conflict-enhanced merge on conflicted commit!");
				}
				
				# return "conflict enhanced" file to the user
				# for cleanup note, this relies on the fact
				# that ikiwiki seems to call rcs_prepedit()
				# again after we return
				return readfile("$config{srcdir}/$file");
			}
			return undef;
		}
		$automator->close();
	}

	# If we reached here then the file we're looking at hasn't changed
	# since $oldrev. Commit it.

	if (system("mtn", "--root=$config{mtnrootdir}", "commit", "--quiet",
	           "--author", $author, "--key", $config{mtnkey}, "-m",
		   possibly_foolish_untaint($message), $file) != 0) {
		debug("Traditional commit failed! Returning data as conflict.");
		my $conflict=readfile("$config{srcdir}/$file");
		if (system("mtn", "--root=$config{mtnrootdir}", "revert",
		           "--quiet", $file) != 0) {
			debug("monotone revert failed");
		}
		return $conflict;
	}
	if (defined($config{mtnsync}) && $config{mtnsync}) {
		if (system("mtn", "--root=$config{mtnrootdir}", "push",
		           "--quiet", "--ticker=none", "--key",
		           $config{mtnkey}) != 0) {
			debug("monotone push failed");
		}
	}

	return undef # success
} #}}}

sub rcs_commit_staged ($$$) {
	# Commits all staged changes. Changes can be staged using rcs_add,
	# rcs_remove, and rcs_rename.
	my ($message, $user, $ipaddr)=@_;
	
	error("rcs_commit_staged not implemented for monotone"); # TODO
}

sub rcs_add ($) { #{{{
	my $file=shift;

	check_config();

	if (system("mtn", "--root=$config{mtnrootdir}", "add", "--quiet",
	           $file) != 0) {
		error("Monotone add failed");
	}
} #}}}

sub rcs_remove ($) { # {{{
	my $file = shift;

	error("rcs_remove not implemented for monotone"); # TODO
} #}}}

sub rcs_rename ($$) { # {{{
	my ($src, $dest) = @_;

	error("rcs_rename not implemented for monotone"); # TODO
} #}}}

sub rcs_recentchanges ($) { #{{{
	my $num=shift;
	my @ret;

	check_config();

	# use log --brief to get a list of revs, as this
	# gives the results in a nice order
	# (otherwise we'd have to do our own date sorting)

	my @revs;

	my $child = open(MTNLOG, "-|");
	if (! $child) {
		exec("mtn", "log", "--root=$config{mtnrootdir}", "--no-graph",
		     "--brief") || error("mtn log failed to run");
	}

	while (($num >= 0) and (my $line = <MTNLOG>)) {
		if ($line =~ m/^($sha1_pattern)/) {
			push @revs, $1;
			$num -= 1;
		}
	}
	close MTNLOG || debug("mtn log exited $?");

	my $automator = Monotone->new();
	$automator->open(undef, $config{mtnrootdir});

	while (@revs != 0) {
		my $rev = shift @revs;
		# first go through and figure out the messages, etc

		my $certs = [read_certs($automator, $rev)];
		
		my $user;
		my $when;
		my $committype;
		my (@pages, @message);
		
		foreach my $cert (@$certs) {
			if ($cert->{signature} eq "ok" &&
			    $cert->{trust} eq "trusted") {
				if ($cert->{name} eq "author") {
					$user = $cert->{value};
				 	# detect the source of the commit
					# from the changelog
					if ($cert->{key} eq $config{mtnkey}) {
						$committype = "web";
					} else {
						$committype = "monotone";
					}
				} elsif ($cert->{name} eq "date") {
					$when = str2time($cert->{value}, 'UTC');
				} elsif ($cert->{name} eq "changelog") {
					my $messageText = $cert->{value};
					# split the changelog into multiple
					# lines
					foreach my $msgline (split(/\n/, $messageText)) {
						push @message, { line => $msgline };
					}
				}
			}
		}
		
		my @changed_files = get_changed_files($automator, $rev);
		my $file;
		
		my ($out, $err) = $automator->call("parents", $rev);
		my @parents = ($out =~ m/^($sha1_pattern)$/);
		my $parent = $parents[0];

		foreach $file (@changed_files) {
			next unless length $file;
			
			if (defined $config{diffurl} and (@parents == 1)) {
				my $diffurl=$config{diffurl};
				$diffurl=~s/\[\[r1\]\]/$parent/g;
				$diffurl=~s/\[\[r2\]\]/$rev/g;
				$diffurl=~s/\[\[file\]\]/$file/g;
				push @pages, {
					page => pagename($file),
					diffurl => $diffurl,
				};
			}
			else {
				push @pages, {
					page => pagename($file),
				}
			}
		}
		
		push @ret, {
			rev => $rev,
			user => $user,
			committype => $committype,
			when => $when,
			message => [@message],
			pages => [@pages],
		} if @pages;
	}

	$automator->close();

	return @ret;
} #}}}

sub rcs_diff ($) { #{{{
	# TODO
} #}}}

sub rcs_getctime ($) { #{{{
	my $file=shift;

	check_config();

	my $child = open(MTNLOG, "-|");
	if (! $child) {
		exec("mtn", "log", "--root=$config{mtnrootdir}", "--no-graph",
		     "--brief", $file) || error("mtn log $file failed to run");
	}

	my $firstRev;
	while (<MTNLOG>) {
		if (/^($sha1_pattern)/) {
			$firstRev=$1;
		}
	}
	close MTNLOG || debug("mtn log $file exited $?");

	if (! defined $firstRev) {
		debug "failed to parse mtn log for $file";
		return 0;
	}

	my $automator = Monotone->new();
	$automator->open(undef, $config{mtnrootdir});

	my $certs = [read_certs($automator, $firstRev)];

	$automator->close();

	my $date;

	foreach my $cert (@$certs) {
		if ($cert->{signature} eq "ok" && $cert->{trust} eq "trusted") {
			if ($cert->{name} eq "date") {
				$date = $cert->{value};
			}
		}
	}

	if (! defined $date) {
		debug "failed to find date cert for revision $firstRev when looking for creation time of $file";
		return 0;
	}

	$date=str2time($date, 'UTC');
	debug("found ctime ".localtime($date)." for $file");
	return $date;
} #}}}

1
