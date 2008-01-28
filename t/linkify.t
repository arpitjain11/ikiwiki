#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 16;

BEGIN { use_ok("IkiWiki"); }

sub linkify ($$$$) {
	my $lpage=shift;
	my $page=shift;

	my $content=shift;
	my @existing_pages=@{shift()};
	
	# This is what linkify and htmllink need set right now to work.
	# This could change, if so, update it..
	%IkiWiki::pagecase=();
	%links=();
	foreach my $page (@existing_pages) {
		$IkiWiki::pagecase{lc $page}=$page;
		$links{$page}=[];
		$renderedfiles{"$page.mdwn"}=[$page];
		$destsources{$page}="$page.mdwn";
	}
	%config=IkiWiki::defaultconfig();
	$config{cgiurl}="http://somehost/ikiwiki.cgi";
	$config{srcdir}=$config{destdir}="/dev/null"; # placate checkconfig
	# currently coded for non usedirs mode (TODO: check both)
	$config{usedirs}=0;

	# currently coded for prefix_directives=0 (TODO: check both)
	# Not setting $config{prefix_directives}=0 explicitly; instead, let the
	# tests break if the default changes, as a reminder to update the
	# tests.

	IkiWiki::checkconfig();

	return IkiWiki::linkify($lpage, $page, $content);
}

sub links_to ($$) {
	my $link=shift;
	my $content=shift;
	
	if ($content =~ m!<a href="[^"]*\Q$link\E[^"]*">!) {
		return 1;
	}
	else {
		print STDERR "# expected link to $link in $content\n";
		return;
	}
}

sub not_links_to ($$) {
	my $link=shift;
	my $content=shift;
	
	if ($content !~ m!<a href="[^"]*\Q$link\E[^"]*">!) {
		return 1;
	}
	else {
		print STDERR "# expected no link to $link in $content\n";
		return;
	}
}

sub links_text ($$) {
	my $text=shift;
	my $content=shift;
	
	if ($content =~ m!>\Q$text\E</a>!) {
		return 1;
	}
	else {
		print STDERR "# expected link text $text in $content\n";
		return;
	}
}


ok(links_to("bar", linkify("foo", "foo", "link to [[bar]] ok", ["foo", "bar"])), "ok link");
ok(links_to("bar_baz", linkify("foo", "foo", "link to [[bar_baz]] ok", ["foo", "bar_baz"])), "ok link");
ok(not_links_to("bar", linkify("foo", "foo", "link to \\[[bar]] ok", ["foo", "bar"])), "escaped link");
ok(links_to("page=bar", linkify("foo", "foo", "link to [[bar]] ok", ["foo"])), "broken link");
ok(links_to("bar", linkify("foo", "foo", "link to [[baz]] and [[bar]] ok", ["foo", "baz", "bar"])), "dual links");
ok(links_to("baz", linkify("foo", "foo", "link to [[baz]] and [[bar]] ok", ["foo", "baz", "bar"])), "dual links");
ok(links_to("bar", linkify("foo", "foo", "link to [[some_page|bar]] ok", ["foo", "bar"])), "named link");
ok(links_text("some page", linkify("foo", "foo", "link to [[some_page|bar]] ok", ["foo", "bar"])), "named link text");
ok(not_links_to("bar", linkify("foo", "foo", "link to [[some page|bar]] ok", ["foo", "bar"])), "named link, with whitespace");
ok(not_links_to("bar", linkify("foo", "foo", "link to [[some page|bar]] ok", ["foo", "bar"])), "named link text, with whitespace");
ok(links_text("0", linkify("foo", "foo", "link to [[0|bar]] ok", ["foo", "bar"])), "named link to 0");
ok(links_text("Some long, & complex page name.", linkify("foo", "foo", "link to [[Some_long,_&_complex_page_name.|bar]] ok, and this is not a link]] here", ["foo", "bar"])), "complex named link text");
ok(links_to("foo/bar", linkify("foo/item", "foo", "link to [[bar]] ok", ["foo", "foo/item", "foo/bar"])), "inline page link");
ok(links_to("bar", linkify("foo", "foo", "link to [[bar]] ok", ["foo", "foo/item", "foo/bar"])), "same except not inline");
ok(links_to("bar#baz", linkify("foo", "foo", "link to [[bar#baz]] ok", ["foo", "bar"])), "anchor link");
