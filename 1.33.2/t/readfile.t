#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 3;
use Encode;

BEGIN { use_ok("IkiWiki"); }

# should read files as utf8
ok(Encode::is_utf8(readfile("t/test1.mdwn"), 1));
is(readfile("t/test1.mdwn"),
	Encode::decode_utf8('![o](../images/o.jpg "ó")'."\n".'óóóóó'."\n"));
