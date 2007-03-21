# Build static html docs suitable for being shipped in the software
# package. This depends on ikiwiki being installed to build the docs.

ifeq ($(shell which ikiwiki),)
IKIWIKI=echo "** ikiwiki not found" >&2 ; echo ikiwiki
else
IKIWIKI=ikiwiki
endif

all:
	$(IKIWIKI) `pwd` html -v --plugin=goodstuff \
		--no-rcs --exclude=/discussion --exclude=html --no-discussion

clean:
	rm -rf .ikiwiki html
