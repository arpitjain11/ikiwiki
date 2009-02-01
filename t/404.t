#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 17;

BEGIN { use_ok("IkiWiki::Plugin::404"); }

sub cgi_page_from_404 {
	return IkiWiki::Plugin::404::cgi_page_from_404(shift, shift, shift);
}

$IkiWiki::config{htmlext} = 'html';

is(cgi_page_from_404('/', 'http://example.com', 1), 'index');
is(cgi_page_from_404('/index.html', 'http://example.com', 0), 'index');
is(cgi_page_from_404('/', 'http://example.com/', 1), 'index');
is(cgi_page_from_404('/index.html', 'http://example.com/', 0), 'index');

is(cgi_page_from_404('/~user/foo/bar', 'http://example.com/~user', 1),
   'foo/bar');
is(cgi_page_from_404('/~user/foo/bar/index.html', 'http://example.com/~user', 1),
   'foo/bar');
is(cgi_page_from_404('/~user/foo/bar/', 'http://example.com/~user', 1),
   'foo/bar');
is(cgi_page_from_404('/~user/foo/bar.html', 'http://example.com/~user', 0),
   'foo/bar');

is(cgi_page_from_404('/~user/foo/bar', 'http://example.com/~user/', 1),
   'foo/bar');
is(cgi_page_from_404('/~user/foo/bar/index.html', 'http://example.com/~user/', 1),
   'foo/bar');
is(cgi_page_from_404('/~user/foo/bar/', 'http://example.com/~user/', 1),
   'foo/bar');
is(cgi_page_from_404('/~user/foo/bar.html', 'http://example.com/~user/', 0),
   'foo/bar');

is(cgi_page_from_404('/~user/foo', 'https://example.com/~user', 1),
   'foo');
is(cgi_page_from_404('/~user/foo/index.html', 'https://example.com/~user', 1),
   'foo');
is(cgi_page_from_404('/~user/foo/', 'https://example.com/~user', 1),
   'foo');
is(cgi_page_from_404('/~user/foo.html', 'https://example.com/~user', 0),
   'foo');
