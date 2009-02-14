#!/usr/bin/perl
package IkiWiki::Plugin::shortcut;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "shortcut", call => \&getsetup);
	hook(type => "checkconfig", id => "shortcut", call => \&checkconfig);
	hook(type => "preprocess", id => "shortcut", call => \&preprocess_shortcut);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub checkconfig () {
	if (defined $config{srcdir} && length $config{srcdir}) {
		# Preprocess the shortcuts page to get all the available shortcuts
		# defined before other pages are rendered.
		my $srcfile=srcfile("shortcuts.".$config{default_pageext}, 1);
		if (! defined $srcfile) {
			$srcfile=srcfile("shortcuts.mdwn", 1);
		}
		if (! defined $srcfile) {
			print STDERR sprintf(gettext("shortcut plugin will not work without %s"),
				"shortcuts.".$config{default_pageext})."\n";
		}
		else {
			IkiWiki::preprocess("shortcuts", "shortcuts", readfile($srcfile));
		}
	}
}

sub preprocess_shortcut (@) {
	my %params=@_;

	if (! defined $params{name} || ! defined $params{url}) {
		error gettext("missing name or url parameter");
	}

	hook(type => "preprocess", no_override => 1, id => $params{name},
		shortcut => 1,
		call => sub { shortcut_expand($params{url}, $params{desc}, @_) });

	#translators: This is used to display what shortcuts are defined.
	#translators: First parameter is the name of the shortcut, the second
	#translators: is an URL.
	return sprintf(gettext("shortcut %s points to <i>%s</i>"), $params{name}, $params{url});
}

sub shortcut_expand ($$@) {
	my $url=shift;
	my $desc=shift;
	my %params=@_;

	# Get params in original order.
	my @params;
	while (@_) {
		my $key=shift;
		my $value=shift;
		push @params, $key if ! length $value;
	}

	# If the shortcuts page changes, all pages that use shortcuts will
	# need to be updated.
	add_depends($params{destpage}, "shortcuts");

	my $text=join(" ", @params);
	my $encoded_text=$text;
	$encoded_text=~s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	
	$url=~s{\%([sS])}{
		$1 eq 's' ? $encoded_text : $text
	}eg;

	$text=~s/_/ /g;
	if (defined $params{desc}) {
		$desc=$params{desc};
	}
	if (defined $desc) {
		$desc=~s/\%s/$text/g;
	}
	else {
		$desc=$text;
	}

	return "<a href=\"$url\">$desc</a>";
}

1
