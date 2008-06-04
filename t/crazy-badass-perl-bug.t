#!/usr/bin/perl
# DO NOT CHANGE ANYTHING IN THIS FILE.
# THe crazy bug reproduced here will go away if any of the calls
# to htmlize are changed.
use warnings;
use strict;
use Test::More tests => 102;
use Encode;

BEGIN { use_ok("IkiWiki"); }

# Initialize htmlscrubber plugin
%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";
IkiWiki::loadplugins(); IkiWiki::checkconfig();
ok(IkiWiki::htmlize("foo", "foo", "mdwn", readfile("t/test1.mdwn")));
ok(IkiWiki::htmlize("foo", "foo", "mdwn", readfile("t/test3.mdwn")),
	"wtf?") for 1..100;
