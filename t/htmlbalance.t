#!/usr/bin/perl
use warnings;
use strict;

BEGIN {
	eval q{
		use HTML::TreeBuilder;
		use XML::Atom::Util qw(encode_xml);
	};
	if ($@) {
		eval q{use Test::More skip_all => "HTML::TreeBuilder or XML::Atom::Util not available"};
	}
	else {
		eval q{use Test::More tests => 7};
	}
	use_ok("IkiWiki::Plugin::htmlbalance");
}

is(IkiWiki::Plugin::htmlbalance::sanitize(content => "<br></br>"), "<br />");
is(IkiWiki::Plugin::htmlbalance::sanitize(content => "<div><p b=\"c\">hello world</div>"), "<div><p b=\"c\">hello world</p></div>");
is(IkiWiki::Plugin::htmlbalance::sanitize(content => "<a></a></a>"), "<a></a>");
is(IkiWiki::Plugin::htmlbalance::sanitize(content => "<b>foo <a</b>"), "<b>foo </b>");
is(IkiWiki::Plugin::htmlbalance::sanitize(content => "<b> foo <a</a></b>"), "<b> foo </b>");
is(IkiWiki::Plugin::htmlbalance::sanitize(content => "a>"), "a&gt;");
