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
use IkiWiki 2.00;
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
                              'raw_enabled': 1 }
);
print html[html.find('<body>')+6:html.find('</body>')].strip();
";

sub import { #{{{
	hook(type => "htmlize", id => "rst", call => \&htmlize);
} # }}}

sub htmlize (@) { #{{{
	my %params=@_;
	my $content=$params{content};

	my $pid;
	my $sigpipe=0;
	$SIG{PIPE}=sub { $sigpipe=1 };
	$pid=open2(*IN, *OUT, "python", "-c",  $pyCmnd);
	
	# open2 doesn't respect "use open ':utf8'"
	binmode (IN, ':utf8');
	binmode (OUT, ':utf8');
	
	print OUT $content;
	close OUT;

	local $/ = undef;
	my $ret=<IN>;
	close IN;
	waitpid $pid, 0;

	return $content if $sigpipe;
	$SIG{PIPE}="DEFAULT";

	return $ret;
} # }}}

1
