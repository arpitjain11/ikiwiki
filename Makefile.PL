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

extra_build:
	./ikiwiki doc html --templatedir=templates --underlaydir=basewiki \
		--wikiname="ikiwiki" --verbose --no-rcs \
		--exclude=/discussion --no-discussion \
		--plugin=brokenlinks --plugin=pagecount \
		--plugin=orphans --plugin=haiku --plugin=meta
	./mdwn2man ikiwiki 1 doc/usage.mdwn > ikiwiki.man
	./mdwn2man ikiwiki-mass-rebuild 8 doc/ikiwiki-mass-rebuild.mdwn > ikiwiki-mass-rebuild.man
		
extra_clean:
	rm -rf html doc/.ikiwiki
	rm -f ikiwiki.man ikiwiki-mass-rebuild.man

extra_install:
	install -d $(PREFIX)/share/ikiwiki/templates
	cp templates/* $(PREFIX)/share/ikiwiki/templates

	install -d $(PREFIX)/share/ikiwiki/basewiki
	cp -a basewiki/* $(PREFIX)/share/ikiwiki/basewiki

	install -d $(PREFIX)/share/man/man1
	install ikiwiki.man $(PREFIX)/share/man/man1/ikiwiki.1
	
	install -d $(PREFIX)/share/man/man8
	install ikiwiki-mass-rebuild.man $(PREFIX)/share/man/man8/ikiwiki-mass-rebuild.8
	
	install -d $(PREFIX)/sbin
	install ikiwiki-mass-rebuild $(PREFIX)/sbin

	install -d $(PREFIX)/lib/w3m/cgi-bin
	install ikiwiki-w3m.cgi $(PREFIX)/lib/w3m/cgi-bin
}
}

WriteMakefile(
	'NAME'		=> 'IkiWiki',
	'PM_FILTER'	=> 'grep -v "removed by Makefile"',
	'EXE_FILES'	=> ['ikiwiki'],
);
