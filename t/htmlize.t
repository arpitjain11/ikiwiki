#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 5;
use Encode;

BEGIN { use_ok("IkiWiki"); }

# Initialize htmlscrubber plugin
%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";
IkiWiki::loadplugins();
IkiWiki::checkconfig();

is(IkiWiki::htmlize("foo", "mdwn", "foo\n\nbar\n"), "<p>foo</p>\n\n<p>bar</p>\n",
	"basic");
is(IkiWiki::htmlize("foo", "mdwn", readfile("t/test1.mdwn")),
	Encode::decode_utf8(qq{<p><img src="../images/o.jpg" alt="o" title="&oacute;" />\nóóóóó</p>\n}),
	"utf8; bug #373203");
ok(IkiWiki::htmlize("foo", "mdwn", readfile("t/test2.mdwn")),
	"this file crashes markdown if it's fed in as decoded utf-8");
my $ret=IkiWiki::htmlize("foo", "mdwn", readfile("t/javascript.mdwn"));
ok($ret !~ /GOTCHA/,
	"javascript.mdwn contains a number of attempts at getting
	javascript that contains GOTCHA past the html sanitiser.");
