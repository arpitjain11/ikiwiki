#!/usr/bin/perl
package IkiWiki::Plugin::toggle;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	add_underlay("javascript");
	hook(type => "getsetup", id => "toggle", call => \&getsetup);
	hook(type => "preprocess", id => "toggle",
		call => \&preprocess_toggle);
	hook(type => "preprocess", id => "toggleable",
		call => \&preprocess_toggleable);
	hook(type => "format", id => "toggle", call => \&format);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub genid ($$) {
	my $page=shift;
	my $id=shift;

	$id="$page.$id";

	# make it a legal html id attribute
	$id=~s/[^-a-zA-Z0-9.]/-/g;
	if ($id !~ /^[a-zA-Z]/) {
		$id="id$id";
	}
	return $id;
}

sub preprocess_toggle (@) {
	my %params=(id => "default", text => "more", @_);

	my $id=genid($params{page}, $params{id});
	return "<a class=\"toggle\" href=\"#$id\">$params{text}</a>";
}

sub preprocess_toggleable (@) {
	my %params=(id => "default", text => "", open => "no", @_);

	# Preprocess the text to expand any preprocessor directives
	# embedded inside it.
	$params{text}=IkiWiki::preprocess($params{page}, $params{destpage}, 
		IkiWiki::filter($params{page}, $params{destpage}, $params{text}));
	
	my $id=genid($params{page}, $params{id});
	my $class=(lc($params{open}) ne "yes") ? "toggleable" : "toggleable-open";

	# Should really be a postprocessor directive, oh well. Work around
	# markdown's dislike of markdown inside a <div> with various funky
	# whitespace.
	my ($indent)=$params{text}=~/( +)$/;
	$indent="" unless defined $indent;
	return "<div class=\"$class\" id=\"$id\"></div>\n\n$params{text}\n$indent<div class=\"toggleableend\"></div>";
}

sub format (@) {
        my %params=@_;

	if ($params{content}=~s!(<div class="toggleable(?:-open)?" id="[^"]+">\s*)</div>!$1!g) {
		$params{content}=~s/<div class="toggleableend">//g;
		if (! ($params{content}=~s!^(<body>)!$1.include_javascript($params{page})!em)) {
			# no </body> tag, probably in preview mode
			$params{content}=include_javascript($params{page}, 1).$params{content};
		}
	}
	return $params{content};
}

sub include_javascript ($;$) {
	my $page=shift;
	my $absolute=shift;
	
	return '<script src="'.urlto("ikiwiki.js", $page, $absolute).
		'" type="text/javascript" charset="utf-8"></script>'."\n".
		'<script src="'.urlto("toggle.js", $page, $absolute).
		'" type="text/javascript" charset="utf-8"></script>';
}

1
