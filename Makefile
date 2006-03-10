all:
	./ikiwiki doc html --wikiname="ikiwiki" --verbose

clean:
	rm -rf html
	rm -f doc/.index
