#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 21;
use Encode;

BEGIN { use_ok("IkiWiki"); }
BEGIN { use_ok("IkiWiki::Plugin::link"); }

%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";
IkiWiki::checkconfig();

# tests of the link plugin's renamepage function
sub try {
	my ($page, $oldpage, $newpage, $content)=@_;

	%IkiWiki::pagecase=();
	%links=();
	$IkiWiki::config{userdir}="foouserdir";
	foreach my $page ($page, $oldpage, $newpage) {
		$IkiWiki::pagecase{lc $page}=$page;
		$links{$page}=[];
	}

	IkiWiki::Plugin::link::renamepage(
			page => $page, 
			oldpage => $oldpage,
			newpage => $newpage,
			content => $content,
	);
}
is(try("z", "foo" => "bar", "[[xxx]]"), "[[xxx]]"); # unrelated link
is(try("z", "foo" => "bar", "[[bar]]"), "[[bar]]"); # link already to new page
is(try("z", "foo" => "bar", "[[foo]]"), "[[bar]]"); # basic conversion to new page name
is(try("z", "foo" => "bar", "[[/foo]]"), "[[/bar]]"); # absolute link
is(try("z", "foo" => "bar", "[[Foo]]"), "[[Bar]]"); # preserve case
is(try("z", "x/foo" => "x/bar", "[[x/Foo]]"), "[[x/Bar]]"); # preserve case of subpage
is(try("z", "foo" => "bar", "[[/Foo]]"), "[[/Bar]]"); # preserve case w/absolute
is(try("z", "foo" => "bar", "[[foo]] [[xxx]]"), "[[bar]] [[xxx]]"); # 2 links, 1 converted
is(try("z", "foo" => "bar", "[[xxx|foo]]"), "[[xxx|bar]]"); # conversion w/text
is(try("z", "foo" => "bar", "[[foo#anchor]]"), "[[bar#anchor]]"); # with anchor
is(try("z", "foo" => "bar", "[[xxx|foo#anchor]]"), "[[xxx|bar#anchor]]"); # with anchor
is(try("z", "foo" => "bar", "[[!moo ]]"), "[[!moo ]]"); # preprocessor directive unchanged
is(try("bugs", "bugs/foo" => "wishlist/bar", "[[foo]]"), "[[wishlist/bar]]"); # subpage link
is(try("z", "foo_bar" => "bar", "[[foo_bar]]"), "[[bar]]"); # old link with underscore
is(try("z", "foo" => "bar_foo", "[[foo]]"), "[[bar_foo]]"); # new link with underscore
is(try("z", "foo_bar" => "bar_foo", "[[foo_bar]]"), "[[bar_foo]]"); # both with underscore
is(try("z", "foo" => "bar__".ord("(")."__", "[[foo]]"), "[[bar(]]"); # new link with escaped chars
is(try("z", "foo__".ord("(")."__" => "bar(", "[[foo(]]"), "[[bar(]]"); # old link with escaped chars
is(try("z", "foo__".ord("(")."__" => "bar__".ord(")")."__", "[[foo(]]"), "[[bar)]]"); # both with escaped chars
