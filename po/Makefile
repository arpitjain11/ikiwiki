# List here all source files with translatable strings.
POTFILES=$(sort $(shell find ../IkiWiki -type f -name \*.pm)) \
	../ikiwiki.in ../IkiWiki.pm ../auto.setup

POFILES=$(wildcard *.po)
MOFILES=$(POFILES:.po=.mo)

all: ikiwiki.pot mo

mo: $(MOFILES)

install: all
	for file in $(MOFILES); do \
		lang=`echo $$file | sed 's/\.mo//'`; \
		install -d $(DESTDIR)$(PREFIX)/share/locale/$$lang/LC_MESSAGES/; \
		install -m 0644 $$file $(DESTDIR)$(PREFIX)/share/locale/$$lang/LC_MESSAGES/ikiwiki.mo; \
	done

ikiwiki.pot: $(POTFILES)
	@if perl -e '($$ver)=`xgettext -V | head -n 1`=~/.*\s+([0-9]+\.[0-9]+)/; die "gettext $$ver too old, not updating the pot file\n" if $$ver < 0.16'; then \
		echo "Rebuilding the pot file"; \
		xgettext --from-code=UTF-8 $(POTFILES) -o ikiwiki.pot -Lperl --add-comments=translators; \
	fi

clean:
	rm -f $(MOFILES) messages messages.mo

%.mo: %.po
	msgfmt -o $@ $<

%.po:
	@echo -n "Merging ikiwiki.pot and $@"
	@msgmerge $@ ikiwiki.pot -o $@.new 2>&1
# Typically all that changes was a date or line number. I'd prefer not to
# commit such changes, so detect and ignore them.
	@if [ "`diff $@ $@.new | grep '[<>]' | grep -v '[<>] #:' | wc -l`" -ne 2 ]; then \
		mv -f $@.new $@; \
	else \
		rm -f $@.new; \
	fi
	@msgfmt --statistics $@ 2>&1

check:
	@for file in $(POFILES); do \
		lang=`echo $$file | sed 's/\.po//'`; \
		printf "$$lang: "; \
		msgfmt -o /dev/null -c -v --statistics $$lang.po;\
	done
