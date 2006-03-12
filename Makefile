all:
	./ikiwiki doc templates html --wikiname="ikiwiki" --verbose --nosvn

clean:
	rm -rf html
	rm -rf doc/.ikiwiki
