#!/usr/bin/perl
# Stubs for no revision control.

use warnings;
use strict;
use IkiWiki;

package IkiWiki;

sub rcs_update () {
}

sub rcs_prepedit ($) {
	return ""
}

sub rcs_commit ($$$) {
	return undef # success
}

sub rcs_add ($) {
}

sub rcs_recentchanges ($) {
}

sub rcs_notify () {
}

sub rcs_getctime () {
	error "getctime not implemented";
}

1
