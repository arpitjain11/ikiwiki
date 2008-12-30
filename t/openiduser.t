#!/usr/bin/perl
use warnings;
use strict;

BEGIN {
	eval q{
		use Net::OpenID::VerifiedIdentity;
	};
	if ($@) {
		eval q{use Test::More skip_all => "Net::OpenID::VerifiedIdentity not available"};
	}
	else {
		eval q{use Test::More tests => 9};
	}
	use_ok("IkiWiki::Plugin::openid");
}

# Some typical examples:

# This test, when run by Test::Harness using perl -w, exposes a warning in
# Net::OpenID::VerifiedIdentity. Normally that warning is not displayed, as
# that module does not use warnings. To avoid cluttering the test output,
# disable the -w switch temporarily.
$^W=0;
is(IkiWiki::openiduser('http://josephturian.blogspot.com'), 'josephturian [blogspot.com]');
$^W=1;

is(IkiWiki::openiduser('http://yam655.livejournal.com/'), 'yam655 [livejournal.com]');
is(IkiWiki::openiduser('http://id.mayfirst.org/jamie/'), 'jamie [id.mayfirst.org]');

# and some less typical ones taken from the ikiwiki commit history

is(IkiWiki::openiduser('http://thm.id.fedoraproject.org/'), 'thm [id.fedoraproject.org]');
is(IkiWiki::openiduser('http://dtrt.org/'), 'dtrt.org');
is(IkiWiki::openiduser('http://alcopop.org/me/openid/'), 'openid [alcopop.org/me]');
is(IkiWiki::openiduser('http://id.launchpad.net/882/bielawski1'), 'bielawski1 [id.launchpad.net/882]');
is(IkiWiki::openiduser('http://technorati.com/people/technorati/drajt'), 'drajt [technorati.com/people/technorati]');
