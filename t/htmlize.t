#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 5;
use Encode;

BEGIN { use_ok("IkiWiki"); }
BEGIN { use_ok("IkiWiki::Render"); }

# Initialize htmlscrubber plugin
%IkiWiki::config=IkiWiki::defaultconfig();
$IkiWiki::config{srcdir}=$IkiWiki::config{destdir}="/dev/null";
IkiWiki::loadplugins();
IkiWiki::checkconfig();

is(IkiWiki::htmlize("foo", "mdwn", "foo\n\nbar\n"), "<p>foo</p>\n\n<p>bar</p>\n",
	"basic");
is(IkiWiki::htmlize("foo", "mdwn", IkiWiki::readfile("t/test1.mdwn")),
	Encode::decode_utf8(qq{<p><img src="../images/o.jpg" alt="o" title="&oacute;" />\nóóóóó</p>\n}),
	"utf8; bug #373203");
ok(IkiWiki::htmlize("foo", "mdwn", IkiWiki::readfile("t/test2.mdwn")),
	"this file crashes markdown if it's fed in as decoded utf-8");
