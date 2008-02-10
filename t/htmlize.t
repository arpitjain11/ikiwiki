#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 26;
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

sub gotcha {
	my $html=IkiWiki::htmlize("foo", "mdwn", shift);
	return $html =~ /GOTCHA/;
}
ok(!gotcha(q{<a href="javascript:alert('GOTCHA')">click me</a>}),
	"javascript url");
ok(!gotcha(q{<a href="javascript&#x3A;alert('GOTCHA')">click me</a>}),
	"partially encoded javascript url");
ok(!gotcha(q{<a href="jscript:alert('GOTCHA')">click me</a>}),
	"jscript url");
ok(!gotcha(q{<a href="vbscript:alert('GOTCHA')">click me</a>}),
	"vbscrpt url");
ok(!gotcha(q{<a href="java	script:alert('GOTCHA')">click me</a>}),
	"java-tab-script url");
ok(!gotcha(q{<span style="&#x61;&#x6e;&#x79;&#x3a;&#x20;&#x65;&#x78;&#x70;&#x72;&#x65;&#x73;&#x73;&#x69;&#x6f;(GOTCHA)&#x6e;&#x28;&#x77;&#x69;&#x6e;&#x64;&#x6f;&#x77;&#x2e;&#x6c;&#x6f;&#x63;&#x61;&#x74;&#x69;&#x6f;&#x6e;&#x3d;&#x27;&#x68;&#x74;&#x74;&#x70;&#x3a;&#x2f;&#x2f;&#x65;&#x78;&#x61;&#x6d;&#x70;&#x6c;&#x65;&#x2e;&#x6f;&#x72;&#x67;&#x2f;&#x27;&#x29;">foo</span>}),
	"entity-encoded CSS script test");
ok(!gotcha(q{<span style="&#97;&#110;&#121;&#58;&#32;&#101;&#120;&#112;&#114;&#101;&#115;&#115;&#105;&#111;&#110;(GOTCHA)&#40;&#119;&#105;&#110;&#100;&#111;&#119;&#46;&#108;&#111;&#99;&#97;&#116;&#105;&#111;&#110;&#61;&#39;&#104;&#116;&#116;&#112;&#58;&#47;&#47;&#101;&#120;&#97;&#109;&#112;&#108;&#101;&#46;&#111;&#114;&#103;&#47;&#39;&#41;">foo</span>}),
	"another entity-encoded CSS script test");
ok(!gotcha(q{<script>GOTCHA</script>}),
	"script tag");
ok(!gotcha(q{<form action="javascript:alert('GOTCHA')">foo</form>}),
	"form action with javascript");
ok(!gotcha(q{<video poster="javascript:alert('GOTCHA')" href="foo.avi">foo</video>}),
	"video poster with javascript");
ok(!gotcha(q{<span style="background: url(javascript:window.location=GOTCHA)">a</span>}),
	"CSS script test");
ok(! gotcha(q{<img src="data:text/javascript;GOTCHA">}),
	"data:text/javascript (jeez!)");
ok(gotcha(q{<img src="data:image/png;base64,GOTCHA">}), "data:image/png");
ok(gotcha(q{<img src="data:image/gif;base64,GOTCHA">}), "data:image/gif");
ok(gotcha(q{<img src="data:image/jpeg;base64,GOTCHA">}), "data:image/jpeg");
ok(gotcha(q{<p>javascript:alert('GOTCHA')</p>}),
	"not javascript AFAIK (but perhaps some web browser would like to
	be perverse and assume it is?)");
ok(gotcha(q{<img src="javascript.png?GOTCHA">}), "not javascript");
ok(gotcha(q{<a href="javascript.png?GOTCHA">foo</a>}), "not javascript");
is(IkiWiki::htmlize("foo", "mdwn",
	q{<img alt="foo" src="foo.gif">}),
	q{<p><img alt="foo" src="foo.gif"></p>
}, "img with alt tag allowed");
is(IkiWiki::htmlize("foo", "mdwn",
	q{<a href="http://google.com/">}),
	q{<p><a href="http://google.com/"></p>
}, "absolute url allowed");
is(IkiWiki::htmlize("foo", "mdwn",
	q{<a href="foo.html">}),
	q{<p><a href="foo.html"></p>
}, "relative url allowed");
is(IkiWiki::htmlize("foo", "mdwn",
	q{<span class="foo">bar</span>}),
	q{<p><span class="foo">bar</span></p>
}, "class attribute allowed");
