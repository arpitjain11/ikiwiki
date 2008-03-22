#!/usr/bin/perl
use warnings;
use strict;
use IkiWiki;

package IkiWiki; # use internal variables
use Test::More tests => 27;

$config{wikistatedir}="/tmp/ikiwiki-test.$$";
system "rm -rf $config{wikistatedir}";

ok(! loadindex(), "loading nonexistent index file");

# Load standard plugins.
ok(loadplugin("meta"), "meta plugin loaded");
ok(loadplugin("mdwn"), "mdwn plugin loaded");

# Set up a default state.
$pagesources{"Foo"}="Foo.mdwn";
$pagesources{"bar"}="bar.mdwn";
$pagesources{"bar.png"}="bar.png";
my $now=time();
$pagemtime{"Foo"}=$now;
$pagemtime{"bar"}=$now-1000;
$pagemtime{"bar.png"}=$now;
$pagectime{"Foo"}=$now;
$pagectime{"bar"}=$now-100000;
$pagectime{"bar.png"}=$now-100000;
$renderedfiles{"Foo"}=["Foo.html"];
$renderedfiles{"bar"}=["bar.html", "bar.rss", "sparkline-foo.gif"];
$renderedfiles{"bar.png"}=["bar.png"];
$links{"Foo"}=["bar.png"];
$links{"bar"}=["Foo", "new-page"];
$links{"bar.png"}=[];
$depends{"Foo"}="";
$depends{"bar"}="foo*";
$depends{"bar.png"}="";
$pagestate{"bar"}{meta}{title}="a page about bar";
$pagestate{"bar"}{meta}{moo}="mooooo";
# only loaded plugins save state, so this should not be saved out
$pagestate{"bar"}{nosuchplugin}{moo}="mooooo";

ok(saveindex(), "save index");
ok(-s "$config{wikistatedir}/indexdb", "index file created");

# Clear state.
%oldrenderedfiles=%pagectime=();
%pagesources=%pagemtime=%oldlinks=%links=%depends=
%destsources=%renderedfiles=%pagecase=%pagestate=();

ok(loadindex(), "load index");
is_deeply(\%pagesources, {
	Foo => "Foo.mdwn",
	bar => "bar.mdwn",
	"bar.png" => "bar.png",
}, "%pagesources loaded correctly");
is_deeply(\%pagemtime, {
	Foo => $now,
	bar => $now-1000,
	"bar.png" => $now,
}, "%pagemtime loaded correctly");
is_deeply(\%pagectime, {
	Foo => $now,
	bar => $now-100000,
	"bar.png" => $now-100000,
}, "%pagemtime loaded correctly");
is_deeply(\%renderedfiles, {
	Foo => ["Foo.html"],
	bar => ["bar.html", "bar.rss", "sparkline-foo.gif"],
	"bar.png" => ["bar.png"],
}, "%renderedfiles loaded correctly");
is_deeply(\%oldrenderedfiles, {
	Foo => ["Foo.html"],
	bar => ["bar.html", "bar.rss", "sparkline-foo.gif"],
	"bar.png" => ["bar.png"],
}, "%oldrenderedfiles loaded correctly");
is_deeply(\%links, {
	Foo => ["bar.png"],
	bar => ["Foo", "new-page"],
	"bar.png" => [],
}, "%links loaded correctly");
is_deeply(\%depends, {
	Foo => "",
	bar => "foo*",
	"bar.png" => "",
}, "%depends loaded correctly");
is_deeply(\%pagestate, {
	bar => {
		meta => {
			title => "a page about bar",
			moo => "mooooo",
		},
	},
}, "%pagestate loaded correctly");
is_deeply(\%pagecase, {
	foo => "Foo",
	bar => "bar",
	"bar.png" => "bar.png"
}, "%pagecase generated correctly");
is_deeply(\%destsources, {
	"Foo.html" => "Foo",
	"bar.html" => "bar",
	"bar.rss" => "bar",
	"sparkline-foo.gif" => "bar",
	"bar.png" => "bar.png",
}, "%destsources generated correctly");

# Clear state.
%oldrenderedfiles=%pagectime=();
%pagesources=%pagemtime=%oldlinks=%links=%depends=
%destsources=%renderedfiles=%pagecase=%pagestate=();

# When state is loaded for a wiki rebuild, only ctime and oldrenderedfiles
# are retained.
$config{rebuild}=1;
ok(loadindex(), "load index");
is_deeply(\%pagesources, {
}, "%pagesources loaded correctly");
is_deeply(\%pagemtime, {
}, "%pagemtime loaded correctly");
is_deeply(\%pagectime, {
	Foo => $now,
	bar => $now-100000,
	"bar.png" => $now-100000,
}, "%pagemtime loaded correctly");
is_deeply(\%renderedfiles, {
}, "%renderedfiles loaded correctly");
is_deeply(\%oldrenderedfiles, {
	Foo => ["Foo.html"],
	bar => ["bar.html", "bar.rss", "sparkline-foo.gif"],
	"bar.png" => ["bar.png"],
}, "%oldrenderedfiles loaded correctly");
is_deeply(\%links, {
}, "%links loaded correctly");
is_deeply(\%depends, {
}, "%depends loaded correctly");
is_deeply(\%pagestate, {
}, "%pagestate loaded correctly");
is_deeply(\%pagecase, {
}, "%pagecase generated correctly");
is_deeply(\%destsources, {
}, "%destsources generated correctly");

system "rm -rf $config{wikistatedir}";
