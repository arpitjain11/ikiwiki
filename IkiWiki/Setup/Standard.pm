#!/usr/bin/perl
# Standard ikiwiki setup module.
# Parameters to import should be all the standard ikiwiki config stuff,
# plus an array of wrappers to set up.

package IkiWiki::Setup::Standard;

use warnings;
use strict;

sub import {
	$IkiWiki::Setup::raw_setup=$_[1];
}

1
