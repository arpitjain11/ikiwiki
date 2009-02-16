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

# Additional configurable path variables.
W3M_CGI_BIN?=$(PREFIX)/lib/w3m/cgi-bin

tflag=$(shell if [ -n "$$NOTAINT" ] && [ "$$NOTAINT" != 1 ]; then printf -- "-T"; fi)
extramodules=$(shell if [ "$$PROFILE" = 1 ]; then printf -- "-d:Profile"; fi)

ikiwiki.out: ikiwiki.in
	./pm_filter $(PREFIX) $(VER) $(PROBABLE_INST_LIB) < ikiwiki.in > ikiwiki.out
	chmod +x ikiwiki.out

ikiwiki.setup: ikiwiki.out
	HOME=/home/me $(PERL) -Iblib/lib $(extramodules) $(tflag) ikiwiki.out -libdir . -dumpsetup ikiwiki.setup

extra_build: ikiwiki.out ikiwiki.setup docwiki
	./mdwn2man ikiwiki 1 doc/usage.mdwn > ikiwiki.man
	./mdwn2man ikiwiki-mass-rebuild 8 doc/ikiwiki-mass-rebuild.mdwn > ikiwiki-mass-rebuild.man
	./mdwn2man ikiwiki-makerepo 1 doc/ikiwiki-makerepo.mdwn > ikiwiki-makerepo.man
	./mdwn2man ikiwiki-transition 1 doc/ikiwiki-transition.mdwn > ikiwiki-transition.man
	./mdwn2man ikiwiki-update-wikilist 1 doc/ikiwiki-update-wikilist.mdwn > ikiwiki-update-wikilist.man
	$(MAKE) -C po
	
docwiki: ikiwiki.out
	$(PERL) -Iblib/lib $(extramodules) $(tflag) ikiwiki.out -libdir . -setup docwiki.setup -refresh

extra_clean:
	rm -rf html doc/.ikiwiki
	rm -f *.man ikiwiki.out ikiwiki.setup plugins/*.pyc
	$(MAKE) -C po clean

extra_install:
	install -d $(DESTDIR)$(PREFIX)/share/ikiwiki
	for dir in `cd underlays && find . -follow -type d ! -regex '.*\.svn.*'`; do \
		install -d $(DESTDIR)$(PREFIX)/share/ikiwiki/$$dir; \
		for file in `find underlays/$$dir -follow -maxdepth 1 -type f`; do \
			cp -aL $$file $(DESTDIR)$(PREFIX)/share/ikiwiki/$$dir 2>/dev/null || \
			install -m 644 $$file $(DESTDIR)$(PREFIX)/share/ikiwiki/$$dir; \
		done; \
	done

	# The directive docs become their own special underlay.
	install -d $(DESTDIR)$(PREFIX)/share/ikiwiki/directives/ikiwiki/directive
	for file in doc/ikiwiki/directive/*; do \
		if [ -f "$$file" ]; then \
			install -m 644 $$file $(DESTDIR)$(PREFIX)/share/ikiwiki/directives/ikiwiki/directive; \
		fi \
	done
	
	# Install example sites.
	for dir in `cd doc/examples; find . -type d ! -regex '.*\.svn.*'`; do \
		install -d $(DESTDIR)$(PREFIX)/share/ikiwiki/examples/$$dir; \
	done
	for file in `cd doc/examples; find . -type f ! -regex '.*\.svn.*'`; do \
		cp -aL doc/examples/$$file $(DESTDIR)$(PREFIX)/share/ikiwiki/examples/$$file 2>/dev/null || \
		install -m 644 doc/examples/$$file $(DESTDIR)$(PREFIX)/share/ikiwiki/examples/$$file; \
	done

	for dir in `find templates -follow -type d ! -regex '.*\.svn.*'`; do \
		install -d $(DESTDIR)$(PREFIX)/share/ikiwiki/$$dir; \
		for file in `find $$dir -follow -maxdepth 1 -type f`; do \
			install -m 644 $$file $(DESTDIR)$(PREFIX)/share/ikiwiki/$$dir; \
		done; \
	done
	
	install -d $(DESTDIR)$(PREFIX)/lib/ikiwiki/plugins
	for file in `find plugins -maxdepth 1 -type f ! -path plugins/.\* ! -name \*demo\* -name \*.py`; do \
		install -m 644 $$file $(DESTDIR)$(PREFIX)/lib/ikiwiki/plugins; \
	done
	for file in `find plugins -maxdepth 1 -type f ! -path plugins/.\* ! -name \*demo\* ! -name \*.py ! -name \*.pyc`; do \
		install -m 755 $$file $(DESTDIR)$(PREFIX)/lib/ikiwiki/plugins; \
	done

	install -d $(DESTDIR)$(PREFIX)/share/man/man1
	install -m 644 ikiwiki.man $(DESTDIR)$(PREFIX)/share/man/man1/ikiwiki.1
	install -m 644 ikiwiki-makerepo.man $(DESTDIR)$(PREFIX)/share/man/man1/ikiwiki-makerepo.1
	install -m 644 ikiwiki-transition.man $(DESTDIR)$(PREFIX)/share/man/man1/ikiwiki-transition.1
	install -m 644 ikiwiki-update-wikilist.man $(DESTDIR)$(PREFIX)/share/man/man1/ikiwiki-update-wikilist.1
	
	install -d $(DESTDIR)$(PREFIX)/share/man/man8
	install -m 644 ikiwiki-mass-rebuild.man $(DESTDIR)$(PREFIX)/share/man/man8/ikiwiki-mass-rebuild.8
	
	install -d $(DESTDIR)$(PREFIX)/sbin
	install ikiwiki-mass-rebuild $(DESTDIR)$(PREFIX)/sbin

	install -d $(DESTDIR)$(W3M_CGI_BIN)
	install ikiwiki-w3m.cgi $(DESTDIR)$(W3M_CGI_BIN)

	install -d $(DESTDIR)$(PREFIX)/bin
	install ikiwiki.out $(DESTDIR)$(PREFIX)/bin/ikiwiki
	install ikiwiki-makerepo ikiwiki-transition ikiwiki-update-wikilist $(DESTDIR)$(PREFIX)/bin/

	$(MAKE) -C po install DESTDIR=$(DESTDIR) PREFIX=$(PREFIX)
	
	# These might fail if a regular user is installing into a home
	# directory.
	-install -d $(DESTDIR)/etc/ikiwiki
	-install -m 0644 wikilist $(DESTDIR)/etc/ikiwiki
	-install -m 0644 auto.setup $(DESTDIR)/etc/ikiwiki
	-install -m 0644 auto-blog.setup $(DESTDIR)/etc/ikiwiki
}
}

WriteMakefile(
	NAME		=> 'IkiWiki',
	PREFIX		=> "/usr/local",
	PM_FILTER	=> './pm_filter $(PREFIX) $(VER) $(PROBABLE_INST_LIB)',
	MAN1PODS	=> {},
	PREREQ_PM	=> {
		'XML::Simple'		=> 0,
		'Text::Markdown'	=> 0,
		'Date::Parse'		=> 0,
		'HTML::Template'	=> 0,
		'HTML::Scrubber'	=> 0,
		'CGI::FormBuilder'	=> 3.02.02,
		'CGI::Session'		=> 0,
		'Mail::Sendmail'	=> 0,
		'HTML::Parser'		=> 0,
		'URI'			=> 0,
		'Data::Dumper'		=> 2.11,
	},
);
