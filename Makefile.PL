#!/usr/bin/perl
use warnings;
use strict;
use ExtUtils::MakeMaker;

# Add a few more targets.
sub MY::postamble {
q{
all:: extra_build
clean:: extra_clean
install:: extra_install
pure_install:: extra_install

VER=$(shell perl -e '$$_=<>;print m/\((.*?)\)/'<debian/changelog)

ikiwiki: ikiwiki.pl
	./pm_filter $(PREFIX) $(VER) < ikiwiki.pl > ikiwiki

extra_build:
	./ikiwiki.pl doc html --templatedir=templates --underlaydir=basewiki \
		--wikiname="ikiwiki" --verbose --no-rcs \
		--exclude=/discussion --no-discussion \
		--plugin=brokenlinks --plugin=pagecount \
		--plugin=orphans --plugin=haiku --plugin=meta \
		--plugin=tag --plugin=polygen --plugin=pagestats \
		--plugin=fortune --plugin=aggregate --plugin=map \
		--plugin=template
	./mdwn2man ikiwiki 1 doc/usage.mdwn > ikiwiki.man
	./mdwn2man ikiwiki-mass-rebuild 8 doc/ikiwiki-mass-rebuild.mdwn > ikiwiki-mass-rebuild.man
		
extra_clean:
	rm -rf html doc/.ikiwiki
	rm -f ikiwiki.man ikiwiki-mass-rebuild.man

extra_install:
	install -d $(DESTDIR)/usr/share/ikiwiki/templates
	cp templates/* $(DESTDIR)/usr/share/ikiwiki/templates

	install -d $(DESTDIR)/usr/share/ikiwiki/basewiki
	cp -a basewiki/* $(DESTDIR)/usr/share/ikiwiki/basewiki

	install -d $(DESTDIR)/usr/share/man/man1
	install ikiwiki.man $(DESTDIR)/usr/share/man/man1/ikiwiki.1
	
	install -d $(DESTDIR)/usr/share/man/man8
	install ikiwiki-mass-rebuild.man $(DESTDIR)/usr/share/man/man8/ikiwiki-mass-rebuild.8
	
	install -d $(DESTDIR)/usr/sbin
	install ikiwiki-mass-rebuild $(DESTDIR)/usr/sbin

	install -d $(DESTDIR)/usr/lib/w3m/cgi-bin
	install ikiwiki-w3m.cgi $(DESTDIR)/usr/lib/w3m/cgi-bin
}
}

WriteMakefile(
	'NAME'		=> 'IkiWiki',
	'PM_FILTER'	=> './pm_filter $(PREFIX) $(VER)',
	'EXE_FILES'	=> ['ikiwiki'],
	'MAN1PODS'	=> {},
	'clean'		=> {FILES => 'ikiwiki'},
);
