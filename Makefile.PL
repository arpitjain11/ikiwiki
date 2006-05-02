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
		--wikiname="ikiwiki" --verbose --nosvn \
		--exclude=/discussion --plugin=brokenlinks \
		--plugin=pagecount
	./mdwn2man doc/usage.mdwn > ikiwiki.man
		
extra_clean:
	rm -rf html doc/.ikiwiki
	rm -f ikiwiki.man

extra_install:
	install -d $(PREFIX)/share/ikiwiki/templates
	cp templates/* $(PREFIX)/share/ikiwiki/templates

	install -d $(PREFIX)/share/ikiwiki/basewiki
	cp -a basewiki/* $(PREFIX)/share/ikiwiki/basewiki

	install -d $(PREFIX)/share/man/man1
	install ikiwiki.man $(PREFIX)/share/man/man1/ikiwiki.1
}
}

WriteMakefile(
	'NAME'		=> 'IkiWiki',
	'PM_FILTER'	=> 'grep -v "removed by Makefile"',
	'EXE_FILES'	=> ['ikiwiki'],
);
