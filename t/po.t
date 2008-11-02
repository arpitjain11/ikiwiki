#!/usr/bin/perl
# -*- cperl-indent-level: 8; -*-
use warnings;
use strict;
use File::Temp;

BEGIN {
	unless (eval { require Locale::Po4a::Chooser }) {
		eval q{
			use Test::More skip_all => "Locale::Po4a::Chooser::new is not available"
		}
	}
	unless (eval { require Locale::Po4a::Po }) {
		eval q{
			use Test::More skip_all => "Locale::Po4a::Po::new is not available"
		}
	}
}

use Test::More tests => 24;

BEGIN { use_ok("IkiWiki"); }

my $msgprefix;

### Init
%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";
## will need this when more thorough tests are written
# $config{srcdir} = "t/po/src";
# $config{destdir} = File::Temp->newdir("ikiwiki-test-po.XXXXXXXXXX", TMPDIR => 1)->dirname;
$config{po_master_language} = { code => 'en',
				name => 'English'
			      };
$config{po_slave_languages} = {
			       es => 'Castellano',
			       fr => "Français"
			      };
$config{po_translatable_pages}='test1 or test2';
$config{po_link_to}='negotiated';
IkiWiki::loadplugins();
IkiWiki::checkconfig();
ok(IkiWiki::loadplugin('po'), "po plugin loaded");

### seed %pagesources and %pagecase
$pagesources{'test1'}='test1.mdwn';
$pagesources{'test1.fr'}='test1.fr.po';
$pagesources{'test2'}='test2.mdwn';
$pagesources{'test2.es'}='test2.es.po';
$pagesources{'test2.fr'}='test2.fr.po';
$pagesources{'test3'}='test3.mdwn';
$pagesources{'test3.es'}='test3.es.mdwn';
foreach my $page (keys %pagesources) {
    $IkiWiki::pagecase{lc $page}=$page;
}

### istranslatable/istranslation
# we run these tests twice because memoization attempts made them
# succeed once every two tries...
ok(IkiWiki::Plugin::po::istranslatable('test2'), "test2 is translatable");
ok(IkiWiki::Plugin::po::istranslatable('test2'), "test2 is translatable");
ok(! IkiWiki::Plugin::po::istranslation('test2'), "test2 is not a translation");
ok(! IkiWiki::Plugin::po::istranslation('test2'), "test2 is not a translation");
ok(! IkiWiki::Plugin::po::istranslatable('test3'), "test3 is not translatable");
ok(! IkiWiki::Plugin::po::istranslatable('test3'), "test3 is not translatable");
ok(! IkiWiki::Plugin::po::istranslation('test3'), "test3 is not a translation");
ok(! IkiWiki::Plugin::po::istranslation('test3'), "test3 is not a translation");

### targetpage
$config{usedirs}=0;
$msgprefix="targetpage (usedirs=0)";
is(targetpage('test1', 'html'), 'test1.en.html', "$msgprefix test1");
is(targetpage('test1.fr', 'html'), 'test1.fr.html', "$msgprefix test1.fr");
$config{usedirs}=1;
$msgprefix="targetpage (usedirs=1)";
is(targetpage('test1', 'html'), 'test1/index.en.html', "$msgprefix test1");
is(targetpage('test1.fr', 'html'), 'test1/index.fr.html', "$msgprefix test1.fr");
is(targetpage('test3', 'html'), 'test3/index.html', "$msgprefix test3 (non-translatable page)");
is(targetpage('test3.es', 'html'), 'test3.es/index.html', "$msgprefix test3.es (non-translatable page)");

### bestlink
$config{po_link_to}='current';
$msgprefix="bestlink (po_link_to=current)";
is(bestlink('test1.fr', 'test2'), 'test2.fr', "$msgprefix test1.fr -> test2");
is(bestlink('test1.fr', 'test2.es'), 'test2.es', "$msgprefix test1.fr -> test2.es");
$config{po_link_to}='negotiated';
$msgprefix="bestlink (po_link_to=negotiated)";
is(bestlink('test1.fr', 'test2'), 'test2', "$msgprefix test1.fr -> test2");
is(bestlink('test1.fr', 'test2.es'), 'test2.es', "$msgprefix test1.fr -> test2.es");

### beautify_urlpath
$config{po_link_to}='default';
$msgprefix="beautify_urlpath (po_link_to=default)";
is(IkiWiki::beautify_urlpath('test1/index.en.html'), './test1/index.en.html', "$msgprefix test1/index.en.html");
is(IkiWiki::beautify_urlpath('test1/index.fr.html'), './test1/index.fr.html', "$msgprefix test1/index.fr.html");
$config{po_link_to}='negotiated';
$msgprefix="beautify_urlpath (po_link_to=negotiated)";
is(IkiWiki::beautify_urlpath('test1/index.en.html'), './test1/', "$msgprefix test1/index.en.html");
is(IkiWiki::beautify_urlpath('test1/index.fr.html'), './test1/index.fr.html', "$msgprefix test1/index.fr.html");
