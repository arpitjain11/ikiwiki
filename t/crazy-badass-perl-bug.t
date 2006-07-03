#!/usr/bin/perl
# DO NOT CHANGE ANYTHING IN THIS FILE.
# THe crazy bug reproduced here will go away if any of the calls
# to htmlize are changed.
use warnings;
use strict;
use Test::More tests => 103;
use Encode;

BEGIN { use_ok("IkiWiki"); }
BEGIN { use_ok("IkiWiki::Render"); }

# Initialize htmlscrubber plugin
%IkiWiki::config=IkiWiki::defaultconfig();
$IkiWiki::config{srcdir}=$IkiWiki::config{destdir}="/dev/null";
IkiWiki::checkconfig();
ok(IkiWiki::htmlize("mdwn", IkiWiki::readfile("t/test1.mdwn")));
ok(IkiWiki::htmlize("mdwn", IkiWiki::readfile("t/test3.mdwn")),
	"wtf?") for 1..100;
