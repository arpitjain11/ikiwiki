#!/usr/bin/perl
# Stubs for no revision control.

use warnings;
use strict;
use IkiWiki;

package IkiWiki;

sub rcs_update () {
	# Update working directory to current version.
	# (May be more complex for distributed RCS.)
}

sub rcs_prepedit ($) {
	# Prepares to edit a file under revision control. Returns a token
	# that must be passed into rcs_commit when the file is ready
	# for committing.
	# The file is relative to the srcdir.
	return ""
}

sub rcs_commit ($$$;$$) {
	# Tries to commit the page; returns undef on _success_ and
	# a version of the page with the rcs's conflict markers on failure.
	# The file is relative to the srcdir.
	return undef # success
}

sub rcs_add ($) {
	# Add a file. The filename is relative to the root of the srcdir.
	# Note that this should not check the new file in, it should only
	# prepare for it to be checked in when rcs_commit is called.
}

sub rcs_recentchanges ($) {
	# Examine the RCS history and generate a list of recent changes.
	# The data structure returned for each change is:
	# {
	# 	rev => # the RCSs id for this commit
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
}

sub rcs_diff ($) {
	# Optional, used to get diffs for recentchanges.
	# The parameter is the rev from rcs_recentchanges.
	return "";
}

sub rcs_getctime ($) {
	# Optional, used to get the page creation time from the RCS.
	error gettext("getctime not implemented");
}

1
