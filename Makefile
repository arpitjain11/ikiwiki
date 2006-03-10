all:
	./ikiwiki doc html --wikiname="ikiwiki" --verbose --offline

clean:
	rm -rf html
	rm -f doc/.index
