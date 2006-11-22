# Build static html docs suitable for being shipped in the software
# package.

all:
	ikiwiki `pwd` html -v --plugin=goodstuff \
		--no-rcs --exclude=/discussion --exclude=html --no-discussion

clean:
	rm -rf .ikiwiki
