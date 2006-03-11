all:
	./ikiwiki doc html --wikiname="ikiwiki" --verbose --nosvn

clean:
	rm -rf html
	rm -f doc/.index
