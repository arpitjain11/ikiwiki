#!/usr/bin/perl
# Very simple reStructuredText processor.
#
# This plugin calls python and requires python-docutils to transform the text
# into html.
#
# Its main problem is that it does not support ikiwiki's WikiLinks nor
# Preprocessor Directives.
#
# Probably Wikilinks and Preprocessor Directives should support a list of
# extensions to process (i.e. the linkify function could be transformed into
# reStructuredText instead of HTML using a hook on rst.py instead of the
# current linkify function)
#
# by Sergio Talens-Oliag <sto@debian.org>

package IkiWiki::Plugin::rst;

use warnings;
use strict;
use IkiWiki;
use IPC::Open2;

# Simple python script, maybe it should be implemented using an external script.
# The settings_overrides are given to avoid potential security risks when
# reading external files or if raw html is included on rst pages.
my $pyCmnd = "
from docutils.core import publish_string;
from sys import stdin;
html = publish_string(stdin.read(), writer_name='html', 
       settings_overrides = { 'halt_level': 6, 
                              'file_insertion_enabled': 0,
                              'raw_enabled': 0 }
);
print html[html.find('<body>')+6:html.find('</body>')].strip();
";

sub import { #{{{
	IkiWiki::hook(type => "htmlize", id => "rst", call => \&htmlize);
} # }}}

sub htmlize (@) { #{{{
	my %params=@_;
	my $content=$params{content};

	my $tries=10;
	my $pid;
	while (1) {
		eval {
			# Try to call python and run our command
			$pid=open2(*IN, *OUT, "python", "-c",  $pyCmnd)
				or return $content;
		};
		last unless $@;
		$tries--;
		if ($tries < 1) {
			IkiWiki::debug("failed to run python to convert rst: $@");
			return $content;
		}
	}
	# open2 doesn't respect "use open ':utf8'"
	binmode (IN, ':utf8');
	binmode (OUT, ':utf8');
	
	print OUT $content;
	close OUT;

	local $/ = undef;
	my $ret=<IN>;
	close IN;
	waitpid $pid, 0;

	return $ret;
} # }}}

1
