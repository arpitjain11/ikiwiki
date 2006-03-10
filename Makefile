all:
	./ikiwiki doc html --wikiname="ikiwiki"

clean:
	rm -rf html
	rm -f doc/.index
