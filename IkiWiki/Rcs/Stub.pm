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

sub rcs_commit ($$$) {
	# Tries to commit the page; returns undef on _success_ and
	# a version of the page with the rcs's conflict markers on failure.
	# The file is relative to the srcdir.
	return undef # success
}

sub rcs_add ($) {
	# Add a file. The filename is relative to the root of the srcdir.
}

sub rcs_recentchanges ($) {
	# Examine the RCS history and generate a data structure for
	# the recentchanges page.
	# This structure is a list of items, each item is a hash reference
	# representing one change to the repo.
	# The hash has keys user (a link to the user making the change),
	# committype (web or the name of the rcs), when (when the change
	# happened, relative to the current time), message (a reference
	# to an array of lines for the commit message), and pages (a
	# reference to an array of links to the pages that were changed).
}

sub rcs_notify () {
	# This function is called when a change is committed to the wiki,
	# and ikiwiki is running as a post-commit hook from the RCS.
	# It should examine the repository to somehow determine what pages
	# changed, and then send emails to users subscribed to those pages.
}

sub rcs_getctime ($) {
	# Optional, used to get the page creation time from the RCS.
	error "getctime not implemented";
}

1
