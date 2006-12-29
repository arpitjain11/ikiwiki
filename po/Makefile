# List here all source files with translatable strings.
POTFILES=$(sort $(shell find ../IkiWiki -type f -name \*.pm)) \
	../ikiwiki.in ../IkiWiki.pm

POFILES=$(wildcard *.po)
MOFILES=$(POFILES:.po=.mo)

all: ikiwiki.pot $(MOFILES)

install: all
	for file in $(MOFILES); do \
		lang=`echo $$file | sed 's/\.mo//'`; \
		install -d $(DESTDIR)$(PREFIX)/share/locale/$$lang/LC_MESSAGES/; \
		install -m 0644 $$file $(DESTDIR)$(PREFIX)/share/locale/$$lang/LC_MESSAGES/ikiwiki.mo; \
	done

ikiwiki.pot: $(POTFILES)
	@echo "Rebuilding the pot file"
	xgettext $(POTFILES) -o ikiwiki.pot -Lperl

clean:
	rm -f ikiwiki.pot $(MOFILES) messages messages.mo

%.mo: %.po
	msgfmt -o $@ $<

%.po: ikiwiki.pot
	@echo -n "Merging ikiwiki.pot and $@"
	@msgmerge $@ ikiwiki.pot -o $@.new
# Typically all that changes was a date. I'd prefer not to commit such
# changes, so detect and ignore them.
	@if [ "`diff $@ $@.new | grep '[<>]' | wc -l`" -ne 2 ]; then \
		mv -f $@.new $@; \
	else \
		rm -f $@.new; \
	fi
	@msgfmt --statistics $@

check:
	@for file in $(POFILES); do \
		lang=`echo $$file | sed 's/\.po//'`; \
		printf "$$lang: "; \
		msgfmt -o /dev/null -c -v --statistics $$lang.po;\
	done
