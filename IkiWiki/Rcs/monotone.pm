#!/usr/bin/perl
use warnings;
use strict;
use IkiWiki;
use Monotone;
use Date::Parse qw(str2time);
use Date::Format qw(time2str);

package IkiWiki;

my $sha1_pattern = qr/[0-9a-fA-F]{40}/; # pattern to validate sha1sums

sub check_config() {
	if (!defined($config{mtnrootdir})) {
		$config{mtnrootdir} = $config{srcdir};
	}
	if (! -d "$config{mtnrootdir}/_MTN") {
		error("Ikiwiki srcdir does not seem to be a Monotone workspace (or set the mtnrootdir)!");
	}
	
	if (!defined($config{mtnmergerc})) {
		$config{mtnmergerc} = "$config{mtnrootdir}/_MTN/mergerc";
	}
	
	chdir $config{srcdir}
	    or error("Cannot chdir to $config{srcdir}: $!");
}

sub get_rev () {
	my $sha1 = `mtn --root=$config{mtnrootdir} automate get_base_revision_id`;

	($sha1) = $sha1 =~ m/($sha1_pattern)/; # sha1 is untainted now
	if (! $sha1) {
		warn("Unable to get base revision for '$config{srcdir}'.")
	}

	return $sha1;
}

sub get_rev_auto ($) {
	my $automator=shift;

	my @results = $automator->call("get_base_revision_id");

	my $sha1 = $results[0];
	($sha1) = $sha1 =~ m/($sha1_pattern)/; # sha1 is untainted now
	if (! $sha1) {
		warn("Unable to get base revision for '$config{srcdir}'.")
	}

	return $sha1;
}

sub mtn_merge ($$$$$) {
    my $leftRev=shift;
    my $rightRev=shift;
    my $branch=shift;
    my $author=shift;
    my $message=shift;	# ignored for the moment because mtn doesn't support it
    
    my $mergeRev;

	my $mergerc = $config{mtnmergerc};
    
	my $child = open(MTNMERGE, "-|");
	if (! $child) {
		open STDERR, ">&STDOUT";
		exec("mtn", "--root=$config{mtnrootdir}", "--rcfile", $mergerc, "explicit_merge", $leftRev, $rightRev, $branch, "--author", $author, "--key", $config{mtnkey}) || error("mtn merge failed to run");
	}

	while (<MTNMERGE>) {
		if (/^mtn.\s.merged.\s($sha1_pattern)$/) {
			$mergeRev=$1;
		}
	}
	
	close MTNMERGE || return undef;

	warn("merged $leftRev, $rightRev to make $mergeRev");

	return $mergeRev;
}

sub commit_file_to_new_rev($$$$$$$$) {
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
	error("Failed to store file data for $wsfilename in repository") if (!defined($newFileID) || 40 != length $newFileID);

	# get the mtn filename rather than the workspace filename
	($out, $err) = $automator->call("get_corresponding_path", $oldrev, $wsfilename, $oldrev);
	my ($filename) = ($out =~ m/^file "(.*)"$/);
	error("Couldn't find monotone repository path for file $wsfilename") if (! $filename);
	warn("Converted ws filename of $wsfilename to repos filename of $filename");

	# then stick in a new revision for this file
	my $manifest =  "format_version \"1\"\n\n".
					"new_manifest [0000000000000000000000000000000000000000]\n\n".
					"old_revision [$oldrev]\n\n".
					"patch \"$filename\"\n".
					" from [$oldFileID]\n".
					"   to [$newFileID]\n";
	($out, $err) = $automator->call("put_revision", $manifest);
	my ($newRevID) = ($out =~ m/^($sha1_pattern)$/);
	error("Unable to make new monotone repository revision") if (!defined($newRevID) || 40 != length $newRevID);
	warn("put revision: $newRevID");
	
	# now we need to add certs for this revision...
	# author, branch, changelog, date
	$automator->call("cert", $newRevID, "author", $author);
	$automator->call("cert", $newRevID, "branch", $branch);
	$automator->call("cert", $newRevID, "changelog", $message);
	$automator->call("cert", $newRevID, "date", time2str("%Y-%m-%dT%T", time, "UTC"));
	
	warn("Added certs for rev: $newRevID");
	return $newRevID;
}

sub check_mergerc() {
	my $mergerc = $config{mtnmergerc};
	if (! -r $mergerc ) {
		warn("$mergerc doesn't exist.  Creating file with default mergers.");
		open(DATA, ">$mergerc") or error("can't open $mergerc $!");
		my $defaultrc = "".
"	function local_execute_redirected(stdin, stdout, stderr, path, ...)\n".
"	   local pid\n".
"	   local ret = -1\n".
"	   io.flush();\n".
"	   pid = spawn_redirected(stdin, stdout, stderr, path, unpack(arg))\n".
"	   if (pid ~= -1) then ret, pid = wait(pid) end\n".
"	   return ret\n".
"	end\n".
"	if (not execute_redirected) then -- use standard function if available\n".
"	   execute_redirected = local_execute_redirected\n".
"	end\n".
"	if (not mergers.fail) then -- use standard merger if available\n".
"	   mergers.fail = {\n".
"	      cmd = function (tbl) return false end,\n".
"	      available = function () return true end,\n".
"	      wanted = function () return true end\n".
"	   }\n".
"	end\n".
"	mergers.diffutils_force = {\n".
"	   cmd = function (tbl)\n".
"	      local ret = execute_redirected(\n".
"	          \"\",\n".
"	          tbl.outfile,\n".
"	          \"\",\n".
"	          \"diff3\",\n".
"	          \"--merge\",\n".
"	          \"--show-overlap\",\n".
"	          \"--label\", string.format(\"[Yours]\",     tbl.left_path ),\n".
"	          \"--label\", string.format(\"[Original]\",  tbl.anc_path  ),\n".
"	          \"--label\", string.format(\"[Theirs]\",    tbl.right_path),\n".
"	          tbl.lfile,\n".
"	          tbl.afile,\n".
"	          tbl.rfile\n".
"	      )\n".
"	      if (ret > 1) then\n".
"	         io.write(gettext(\"Error running GNU diffutils 3-way difference tool 'diff3'\"))\n".
"	         return false\n".
"	      end\n".
"	      return tbl.outfile\n".
"	   end,\n".
"	   available =\n".
"	      function ()\n".
"	          return program_exists_in_path(\"diff3\");\n".
"	      end,\n".
"	   wanted =\n".
"	      function ()\n".
"	           return true\n".
"	      end\n".
"	}\n";
		print DATA $defaultrc;
		close(DATA);
	}
}

sub read_certs ($$) {
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
}

sub get_changed_files ($$) {
	my $automator=shift;
	my $rev=shift;
	
	my @results = $automator->call("get_revision", $rev);
	my $changes=$results[0];

	my @ret;
	my %seen = ();
	
	while ($changes =~ m/\s*(add_file|patch|delete|rename)\s"(.*?)(?<!\\)"\n/sg) {
		my $file = $2;
		if (! $seen{$file}) {	# don't add the same file multiple times
			push @ret, $file;
			$seen{$file} = 1;
		}
	}
	
	return @ret;
}

# The following functions are the ones actually called by Ikiwiki

sub rcs_update () {
	# Update working directory to current version.

	check_config();

	if (defined($config{mtnsync}) && $config{mtnsync}) {
		if (system("mtn", "--root=$config{mtnrootdir}", "sync", "--quiet", "--ticker=none", "--key", $config{mtnkey}) != 0) {
			warn("monotone sync failed before update\n");
		}
	}

	if (system("mtn", "--root=$config{mtnrootdir}", "update", "--quiet") != 0) {
		warn("monotone update failed\n");
	}
}

sub rcs_prepedit ($) {
	# Prepares to edit a file under revision control. Returns a token
	# that must be passed into rcs_commit when the file is ready
	# for committing.
	# The file is relative to the srcdir.
	my $file=shift;

	check_config();

	# For monotone, return the revision of the file when
	# editing begins.
	return get_rev();
}

sub rcs_commit ($$$;$$) {
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
		#$automator->setOpts("-r", $oldrev, "-r", $rev);
		#my ($out, $err) = $automator->call("content_diff", $file);
		#debug("Problem committing $file") if ($err ne "");
		# FIXME: use of $file in these backticks is not wise from a
		# security POV. Probably safe, but should be avoided
		# anyway.
		my $diff = `mtn --root=$config{mtnrootdir} au content_diff -r $oldrev -r $rev $file`; # was just $out;

		if ($diff) {
			# this file has changed
			# commit a revision with just this file changed off
			# the old revision
			# first get the contents
			warn("File changed: forming branch\n");
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
				warn("Unable to revert $file after merge on conflicted commit!");
			}
			warn("Divergence created!  Attempting auto-merge.");

			check_mergerc();

			# see if it will merge cleanly
			$ENV{MTN_MERGE}="fail";
			my $mergeResult = mtn_merge($newRevID, $rev, $branch, $author, "Auto-merging parallel web edits.");
			$ENV{MTN_MERGE}="";

			# push any changes so far
			if (defined($config{mtnsync}) && $config{mtnsync}) {
				if (system("mtn", "--root=$config{mtnrootdir}", "push", "--quiet", "--ticker=none", "--key", $config{mtnkey}) != 0) {
					warn("monotone push failed\n");
				}
			}
			
			if (defined($mergeResult)) {
				# everything is merged - bring outselves up to date
				if (system("mtn", "--root=$config{mtnrootdir}", "update", "-r", $mergeResult) != 0) {
					warn("Unable to update to rev $mergeResult after merge on conflicted commit!");
				}
			} else {
				warn("Auto-merge failed.  Using diff-merge to add conflict markers.");
				
				$ENV{MTN_MERGE}="diffutils_force";
				my $mergeResult = mtn_merge($newRevID, $rev, $branch, $author, "Merge parallel conflicting web edits (adding inline conflict markers).\nThis revision should be cleaned up manually.");
				$ENV{MTN_MERGE}="";
				
				if (!defined($mergeResult)) {
					warn("Unable to insert conflict markers!");
					error("Your commit succeeded.  Unfortunately, someone else committed something to the same\n".
				 		"part of the wiki at the same time.  Both versions are stored in the monotone repository,\n".
						"but at present the different versions cannot be reconciled through the web interface.\n\n".
						"Please use the non-web interface to resolve the conflicts.\n");
				}
				
				# suspend this revision because it has conflict markers...
				if (system("mtn", "--root=$config{mtnrootdir}", "update", "-r", $mergeResult) != 0) {
					warn("Unable to update to rev $mergeResult after conflict-enhanced merge on conflicted commit!");
				}
				
				# return "conflict enhanced" file to the user for cleanup
				# note, this relies on the fact that ikiwiki seems to call rcs_prepedit() again
				# after we return
				return readfile("$config{srcdir}/$file");
			}
			return undef;
		}
		$automator->close();
	}

	# if we reached here then the file we're looking at hasn't changed since $oldrev.  Commit it.

	if (system("mtn", "--root=$config{mtnrootdir}", "commit", "--quiet", "--author", $author, "--key", $config{mtnkey},
				"-m", possibly_foolish_untaint($message), $file) != 0) {
		warn("Traditional commit failed!\nReturning data as conflict.\n");
		my $conflict=readfile("$config{srcdir}/$file");
		if (system("mtn", "--root=$config{mtnrootdir}", "revert", "--quiet", $file) != 0) {
			warn("monotone revert failed\n");
		}
		return $conflict;
	}
	if (defined($config{mtnsync}) && $config{mtnsync}) {
		if (system("mtn", "--root=$config{mtnrootdir}", "sync", "--quiet", "--ticker=none", "--key", $config{mtnkey}) != 0) {
			warn("monotone sync failed\n");
		}
	}

	return undef # success
}

sub rcs_add ($) {
	# Add a file. The filename is relative to the root of the srcdir.
	my $file=shift;

	check_config();

	if (system("mtn", "--root=$config{mtnrootdir}", "add", "--quiet", "$config{srcdir}/$file") != 0) {
		error("Monotone add failed");
	}
}

sub rcs_recentchanges ($) {
	# Examine the RCS history and generate a list of recent changes.
	# The data structure returned for each change is:
	# {
	# 	user => # name of user who made the change,
	# 	committype => # either "web" or the name of the rcs,
	# 	when => # time when the change was made,
	# 	message => [
	# 		{ line => "commit message line" },
	# 		{ line => "commit message line" },
	# 		# etc,
	# 	],
	# 	pages => [
	# 		{
	# 			page => # name of page changed,
	#			diffurl => # optional url to a diff showing 
	#			           # the changes,
	# 		},
	# 		# repeat for each page changed in this commit,
	# 	],
	# }

	my $num=shift;
	my @ret;

	check_config();

	# use log --brief to get a list of revs, as this
	# gives the results in a nice order
	# (otherwise we'd have to do our own date sorting)

	my @revs;

	my $child = open(MTNLOG, "-|");
	if (! $child) {
		exec("mtn", "log", "--root=$config{mtnrootdir}", "--no-graph", "--brief") || error("mtn log failed to run");
	}

	my $line;

	while (($num >= 0) and ($line = <MTNLOG>)) {
		if ($line =~ m/^($sha1_pattern)/) {
			push @revs, $1;
			$num -= 1;
		}
	}
	close MTNLOG || warn "mtn log exited $?";

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
			if ($cert->{signature} eq "ok" && $cert->{trust} eq "trusted") {
				if ($cert->{name} eq "author") {
					$user = $cert->{value};
					# detect the source of the commit from the changelog
					if ($cert->{key} eq $config{mtnkey}) {
						$committype = "web";
					} else {
						$committype = "monotone";
					}
				} elsif ($cert->{name} eq "date") {
					$when = time - str2time($cert->{value}, 'UTC');
				} elsif ($cert->{name} eq "changelog") {
					my $messageText = $cert->{value};
					# split the changelog into multiple lines
					foreach my $msgline (split(/\n/, $messageText)) {
						push @message, { line => $msgline };
					}
				}
			}
		}
		
		my @changed_files = get_changed_files($automator, $rev);
		my $file;
		
		foreach $file (@changed_files) {
			push @pages, {
				page => pagename($file),
			} if length $file;
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
}

sub rcs_notify () {
	# This function is called when a change is committed to the wiki,
	# and ikiwiki is running as a post-commit hook from the RCS.
	# It should examine the repository to somehow determine what pages
	# changed, and then send emails to users subscribed to those pages.
	
	warn("The monotone rcs_notify function is currently untested.  Use at own risk!");
	
	if (! exists $ENV{REV}) {
		error(gettext("REV is not set, not running from mtn post-commit hook, cannot send notifications"));
	}
	if ($ENV{REV} !~ m/($sha1_pattern)/) { # sha1 is untainted now
		error(gettext("REV is not a valid revision identifier, cannot send notifications"));
	}
	my $rev = $1;
	
	check_config();

	my $automator = Monotone->new();
	$automator->open(undef, $config{mtnrootdir});

	my $certs = [read_certs($automator, $rev)];
	my $user;
	my $message;
	my $when;

	foreach my $cert (@$certs) {
		if ($cert->{signature} eq "ok" && $cert->{trust} eq "trusted") {
			if ($cert->{name} eq "author") {
				$user = $cert->{value};
			} elsif ($cert->{name} eq "date") {
				$when = $cert->{value};
			} elsif ($cert->{name} eq "changelog") {
				$message = $cert->{value};
			}
		}
	}
		
	my @changed_pages = get_changed_files($automator, $rev);
	
	$automator->close();
	
	require IkiWiki::UserInfo;
	send_commit_mails(
		sub {
			return $message;
		},
		sub {
			`mtn --root=$config{mtnrootdir} au content_diff -r $rev`;
		}, $user, @changed_pages);
}

sub rcs_getctime ($) {
	# Optional, used to get the page creation time from the RCS.
	# error gettext("getctime not implemented");
	my $file=shift;

	check_config();

	my $child = open(MTNLOG, "-|");
	if (! $child) {
		exec("mtn", "log", "--root=$config{mtnrootdir}", "--no-graph", "--brief", $file) || error("mtn log $file failed to run");
	}

	my $firstRev;
	while (<MTNLOG>) {
		if (/^($sha1_pattern)/) {
			$firstRev=$1;
		}
	}
	close MTNLOG || warn "mtn log $file exited $?";

	if (! defined $firstRev) {
		warn "failed to parse mtn log for $file\n";
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
		warn "failed to find date cert for revision $firstRev when looking for creation time of $file\n";
		return 0;
	}

	$date=str2time($date, 'UTC');
	debug("found ctime ".localtime($date)." for $file");
	return $date;
}
