#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 24;

BEGIN { use_ok("IkiWiki"); }

%config=IkiWiki::defaultconfig();

ok(IkiWiki::file_pruned("src/.ikiwiki/", "src"));
ok(IkiWiki::file_pruned("src/.ikiwiki/index", "src"));
ok(IkiWiki::file_pruned("src/.svn", "src"));
ok(IkiWiki::file_pruned("src/subdir/.svn", "src"));
ok(IkiWiki::file_pruned("src/subdir/.svn/foo", "src"));
ok(IkiWiki::file_pruned("src/.git", "src"));
ok(IkiWiki::file_pruned("src/subdir/.git", "src"));
ok(IkiWiki::file_pruned("src/subdir/.git/foo", "src"));
ok(! IkiWiki::file_pruned("src/svn/fo", "src"));
ok(! IkiWiki::file_pruned("src/git", "src"));
ok(! IkiWiki::file_pruned("src/index.mdwn", "src"));
ok(! IkiWiki::file_pruned("src/index.", "src"));

# these are ok because while the filename starts with ".", the canonpathed
# version does not
ok(! IkiWiki::file_pruned("src/.", "src"));
ok(! IkiWiki::file_pruned("src/./", "src"));

ok(IkiWiki::file_pruned("src/..", "src"));
ok(IkiWiki::file_pruned("src/../", "src"));
ok(IkiWiki::file_pruned("src/../", "src"));

ok(! IkiWiki::file_pruned("src", "src"));
ok(! IkiWiki::file_pruned("/.foo/src", "/.foo/src"));
ok(IkiWiki::file_pruned("/.foo/src/.foo/src", "/.foo/src"));
ok(! IkiWiki::file_pruned("/.foo/src/index.mdwn", "/.foo/src/index.mdwn"));

ok(IkiWiki::file_pruned("x/y/foo.dpkg-tmp", "src"));
ok(IkiWiki::file_pruned("x/y/foo.ikiwiki-new", "src"));
