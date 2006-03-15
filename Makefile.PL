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
	./ikiwiki doc templates html --wikiname="ikiwiki" --verbose \
		--nosvn --exclude=/discussion

extra_clean:
	rm -rf html
	rm -rf doc/.ikiwiki

extra_install:
	install -d $(PREFIX)/share/ikiwiki/templates
	cp templates/* $(PREFIX)/share/ikiwiki/templates
}
}

WriteMakefile(
	'NAME'		=> 'IkiWiki',
	'EXE_FILES'	=> ['ikiwiki'],
);
