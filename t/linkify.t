#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 32;

BEGIN { use_ok("IkiWiki"); }

# Initialize link plugin
%config=IkiWiki::defaultconfig();
IkiWiki::loadplugins();

my $prefix_directives;

sub linkify ($$$$) {
	my $lpage=shift;
	my $page=shift;

	my $content=shift;
	my @existing_pages=@{shift()};
	
	# This is what linkify and htmllink need set right now to work.
	# This could change, if so, update it..
	%IkiWiki::pagecase=();
	%links=();
	foreach my $p (@existing_pages) {
		$IkiWiki::pagecase{lc $p}=$p;
		$links{$p}=[];
		$renderedfiles{"$p.mdwn"}=[$p];
		$destsources{$p}="$p.mdwn";
	}

	%config=IkiWiki::defaultconfig();
	$config{cgiurl}="http://somehost/ikiwiki.cgi";
	$config{srcdir}=$config{destdir}="/dev/null"; # placate checkconfig
	# currently coded for non usedirs mode (TODO: check both)
	$config{usedirs}=0;
	$config{prefix_directives}=$prefix_directives;

	IkiWiki::checkconfig();

	return IkiWiki::linkify($lpage, $page, $content);
}

sub links_to ($$) {
	my $link=shift;
	my $content=shift;
	
	if ($content =~ m!<a href="[^"]*\Q$link\E[^"]*"\s*[^>]*>!) {
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

# Tests that are the same for both styles of prefix directives.
foreach $prefix_directives (0,1) {
	ok(links_to("bar", linkify("foo", "foo", "link to [[bar]] ok", ["foo", "bar"])), "ok link");
	ok(links_to("bar_baz", linkify("foo", "foo", "link to [[bar_baz]] ok", ["foo", "bar_baz"])), "ok link");
	ok(not_links_to("bar", linkify("foo", "foo", "link to \\[[bar]] ok", ["foo", "bar"])), "escaped link");
	ok(links_to("page=bar", linkify("foo", "foo", "link to [[bar]] ok", ["foo"])), "broken link");
	ok(links_to("bar", linkify("foo", "foo", "link to [[baz]] and [[bar]] ok", ["foo", "baz", "bar"])), "dual links");
	ok(links_to("baz", linkify("foo", "foo", "link to [[baz]] and [[bar]] ok", ["foo", "baz", "bar"])), "dual links");
	ok(links_to("bar", linkify("foo", "foo", "link to [[some_page|bar]] ok", ["foo", "bar"])), "named link");
	ok(links_text("some page", linkify("foo", "foo", "link to [[some_page|bar]] ok", ["foo", "bar"])), "named link text");
	ok(links_text("0", linkify("foo", "foo", "link to [[0|bar]] ok", ["foo", "bar"])), "named link to 0");
	ok(links_text("Some long, & complex page name.", linkify("foo", "foo", "link to [[Some_long,_&_complex_page_name.|bar]] ok, and this is not a link]] here", ["foo", "bar"])), "complex named link text");
	ok(links_to("foo/bar", linkify("foo/item", "foo", "link to [[bar]] ok", ["foo", "foo/item", "foo/bar"])), "inline page link");
	ok(links_to("bar",     linkify("foo",      "foo", "link to [[bar]] ok", ["foo", "foo/item", "foo/bar"])), "same except not inline");
	ok(links_to("bar#baz", linkify("foo",      "foo", "link to [[bar#baz]] ok", ["foo", "bar"])), "anchor link");
}

$prefix_directives=0;
ok(not_links_to("some_page", linkify("foo", "foo", "link to [[some page]] ok", ["foo", "bar", "some_page"])),
	"link with whitespace, without prefix_directives");
ok(not_links_to("bar", linkify("foo", "foo", "link to [[some page|bar]] ok", ["foo", "bar"])),
	"named link, with whitespace, without prefix_directives");

$prefix_directives=1;
ok(links_to("some_page", linkify("foo", "foo", "link to [[some page]] ok", ["foo", "bar", "some_page"])),
	"link with whitespace");
ok(links_to("bar", linkify("foo", "foo", "link to [[some page|bar]] ok", ["foo", "bar"])),
	"named link, with whitespace");
ok(links_text("some page", linkify("foo", "foo", "link to [[some page|bar]] ok", ["foo", "bar"])),
	"named link text, with whitespace");
