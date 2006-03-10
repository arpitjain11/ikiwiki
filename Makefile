all:
	./ikiwiki doc html

clean:
	rm -rf html
	rm -f doc/.index
