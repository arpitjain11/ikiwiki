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

PROBABLE_INST_LIB=$(shell \\
	if [ "$(INSTALLDIRS)" = "perl" ]; then \\
		echo $(INSTALLPRIVLIB); \\
	elif [ "$(INSTALLDIRS)" = "site" ]; then \\
		echo $(INSTALLSITELIB); \\
	elif [ "$(INSTALLDIRS)" = "vendor" ]; then \\
		echo $(INSTALLVENDORLIB); \\
	fi \\
)

extra_build:
	./ikiwiki.in doc html --templatedir=templates --underlaydir=basewiki \
		--wikiname="ikiwiki" --verbose --no-rcs \
		--exclude=/discussion --no-discussion \
		--plugin=brokenlinks --plugin=pagecount \
		--plugin=orphans --plugin=haiku --plugin=meta \
		--plugin=tag --plugin=polygen --plugin=pagestats \
		--plugin=fortune --plugin=aggregate --plugin=map \
		--plugin=template --plugin=toc --plugin=shortcut
	./mdwn2man ikiwiki 1 doc/usage.mdwn > ikiwiki.man
	./mdwn2man ikiwiki-mass-rebuild 8 doc/ikiwiki-mass-rebuild.mdwn > ikiwiki-mass-rebuild.man
	./pm_filter $(PREFIX) $(VER) $(PROBABLE_INST_LIB) < ikiwiki.in > ikiwiki.out
		
extra_clean:
	rm -rf html doc/.ikiwiki
	rm -f ikiwiki.man ikiwiki-mass-rebuild.man ikiwiki.out

extra_install:
	install -d $(DESTDIR)$(PREFIX)/share/ikiwiki/templates
	$(CP) -a templates/* $(DESTDIR)$(PREFIX)/share/ikiwiki/templates

	install -d $(DESTDIR)$(PREFIX)/share/ikiwiki/basewiki
	$(CP) -a basewiki/* $(DESTDIR)$(PREFIX)/share/ikiwiki/basewiki

	install -d $(DESTDIR)$(PREFIX)/share/man/man1
	install ikiwiki.man $(DESTDIR)$(PREFIX)/share/man/man1/ikiwiki.1
	
	install -d $(DESTDIR)$(PREFIX)/share/man/man8
	install ikiwiki-mass-rebuild.man $(DESTDIR)$(PREFIX)/share/man/man8/ikiwiki-mass-rebuild.8
	
	install -d $(DESTDIR)$(PREFIX)/sbin
	install ikiwiki-mass-rebuild $(DESTDIR)$(PREFIX)/sbin

	install -d $(DESTDIR)$(PREFIX)/lib/w3m/cgi-bin
	install ikiwiki-w3m.cgi $(DESTDIR)$(PREFIX)/lib/w3m/cgi-bin

	install -d $(DESTDIR)$(PREFIX)/bin
	install ikiwiki.out $(DESTDIR)$(PREFIX)/bin/ikiwiki
}
}

WriteMakefile(
	NAME		=> 'IkiWiki',
	PREFIX		=> "/usr/local",
	PM_FILTER	=> './pm_filter $(PREFIX) $(VER) $(PROBABLE_INST_LIB)',
	MAN1PODS	=> {},
);
