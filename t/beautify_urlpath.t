#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 8;

BEGIN { use_ok("IkiWiki"); }

$IkiWiki::config{usedirs} = 1;
$IkiWiki::config{htmlext} = "HTML";
is(IkiWiki::beautify_urlpath("foo/bar"), "./foo/bar");
is(IkiWiki::beautify_urlpath("../badger"), "../badger");
is(IkiWiki::beautify_urlpath("./bleh"), "./bleh");
is(IkiWiki::beautify_urlpath("foo/index.HTML"), "./foo/");
is(IkiWiki::beautify_urlpath("index.HTML"), "./");
is(IkiWiki::beautify_urlpath("../index.HTML"), "../");
$IkiWiki::config{usedirs} = 0;
is(IkiWiki::beautify_urlpath("foo/index.HTML"), "./foo/index.HTML");
