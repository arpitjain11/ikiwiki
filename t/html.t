#!/usr/bin/perl
use warnings;
use strict;
use Test::More;

my @pages;

BEGIN {
	@pages=qw(index todo features news);
	if (! -x "/usr/bin/validate") {
		plan skip_all => "/usr/bin/validate html validator not present";
	}
	else {
		plan(tests => int @pages + 3);
	}
	use_ok("IkiWiki");
	use_ok("IkiWiki::Render");
}

# Have to build the html pages first.
# Note that just building them like this doesn't exersise all the possible
# html that can be generated, in particular it misses some of the action
# links at the top, etc.
ok(system("make >/dev/null") == 0);

foreach my $page (@pages) {
        print "# Validating $page\n";
	ok(system("validate html/$page.html") == 0);
}

# TODO: validate form output html
