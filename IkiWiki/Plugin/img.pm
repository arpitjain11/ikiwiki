#!/usr/bin/perl
# Ikiwiki enhanced image handling plugin
# Christian Mock cm@tahina.priv.at 20061002
package IkiWiki::Plugin::img;

use warnings;
use strict;
use IkiWiki;
use Image::Magick;

my %imgdefaults;

sub import { #{{{
	hook(type => "preprocess", id => "img", call => \&preprocess);
} #}}}

sub preprocess (@) { #{{{
	my ($image) = $_[0] =~ /$config{wiki_file_regexp}/; # untaint
	my %params=@_;

	if (! exists $imgdefaults{$params{page}}) {
		$imgdefaults{$params{page}} = {};
	}
	my $size = $params{size} || $imgdefaults{$params{page}}->{size} || 'full';
	my $alt = $params{alt} || $imgdefaults{$params{page}}->{alt} || '';

	if ($image eq 'defaults') {
		$imgdefaults{$params{page}} = {
			size => $size,
			alt => $alt,
		};
		return '';
	}

	add_depends($params{page}, $image);
	my $file = bestlink($params{page}, $image) || return "[[img $image not found]]";

	my $dir = IkiWiki::dirname($file);
	my $base = IkiWiki::basename($file);
	my $im = Image::Magick->new;
	my $imglink;
	my $r;

	if ($size ne 'full') {
		my ($w, $h) = ($size =~ /^(\d+)x(\d+)$/);
		return "[[img bad size \"$size\"]]" unless (defined $w && defined $h);

		my $outfile = "$config{destdir}/$dir/${w}x${h}-$base";
		$imglink = "$dir/${w}x${h}-$base";
		will_render($params{page}, $imglink);

		if (-e $outfile && (-M srcfile($file) >= -M $outfile)) {
			$r = $im->Read($outfile);
			return "[[img failed to read $outfile: $r]]" if $r;
		}
		else {
			$r = $im->Read(srcfile($file));
			return "[[img failed to read $file: $r]]" if $r;

			$r = $im->Resize(geometry => "${w}x${h}");
			return "[[img failed to resize: $r]]" if $r;

			my @blob = $im->ImageToBlob();
			writefile($imglink, $config{destdir}, $blob[0], 1);
		}
	}
	else {
		$r = $im->Read(srcfile($file));
		return "[[img failed to read $file: $r]]" if $r;
		$imglink = $file;
	}

	add_depends($imglink, $params{page});

	return '<a href="'.
		IkiWiki::abs2rel($file, IkiWiki::dirname($params{destpage})).
		'"><img src="'.
		IkiWiki::abs2rel($imglink, IkiWiki::dirname($params{destpage})).
		'" alt="'.$alt.'" width="'.$im->Get("width").
		'" height="'.$im->Get("height").'" /></a>';
} #}}}

1;
