all:
	./ikiwiki doc templates html --wikiname="ikiwiki" --verbose \
		--nosvn --exclude=/discussion

clean:
	rm -rf html
	rm -rf doc/.ikiwiki
