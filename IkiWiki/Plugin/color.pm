#!/usr/bin/perl
# Ikiwiki text colouring plugin
# Paweł‚ Tęcza <ptecza@net.icm.edu.pl>
package IkiWiki::Plugin::color;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "preprocess", id => "color", call => \&preprocess);
	hook(type => "format",     id => "color", call => \&format);
}

sub preserve_style ($$$) {
	my $foreground = shift;
	my $background = shift;
	my $text       = shift;

	$foreground = defined $foreground ? lc($foreground) : '';
	$background = defined $background ? lc($background) : '';
	$text       = '' unless (defined $text);

	# Validate colors. Only color name or color code are valid.
	$foreground = '' unless ($foreground &&
				($foreground =~ /^[a-z]+$/ || $foreground =~ /^#[0-9a-f]{3,6}$/));
	$background = '' unless ($background &&
				($background =~ /^[a-z]+$/ || $background =~ /^#[0-9a-f]{3,6}$/));

	my $preserved = '';
	$preserved .= '<span class="color">';
	$preserved .= 'color: '.$foreground if ($foreground);
	$preserved .= '; ' if ($foreground && $background);
	$preserved .= 'background-color: '.$background if ($background);
	$preserved .= '</span>';
	$preserved .= '<span class="colorend">'.$text.'</span>';
	
	return $preserved;

}

sub replace_preserved_style ($) {
	my $content = shift;

	$content =~ s!<span class="color">((color: ([a-z]+|\#[0-9a-f]{3,6})?)?((; )?(background-color: ([a-z]+|\#[0-9a-f]{3,6})?)?)?)</span>!<span class="color" style="$1">!g;
	$content =~ s!<span class="colorend">!!g;

	return $content;
}

sub preprocess (@) {
	my %params = @_;

	# Preprocess the text to expand any preprocessor directives
	# embedded inside it.
	$params{text} = IkiWiki::preprocess($params{page}, $params{destpage},
				IkiWiki::filter($params{page}, $params{destpage}, $params{text}));

	return preserve_style($params{foreground}, $params{background}, $params{text});
}

sub format (@) {
	my %params = @_;

	$params{content} = replace_preserved_style($params{content});
	return $params{content};	
}

1
