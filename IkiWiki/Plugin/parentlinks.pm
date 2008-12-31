#!/usr/bin/perl
# Ikiwiki parentlinks plugin.
package IkiWiki::Plugin::parentlinks;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "parentlinks", id => "parentlinks", call => \&parentlinks);
	hook(type => "pagetemplate", id => "parentlinks", call => \&pagetemplate);
}

sub getsetup () {
	return 
		plugin => {
			safe => 1,
			rebuild => 1,
		},
}

sub parentlinks ($) {
	my $page=shift;

	my @ret;
	my $path="";
	my $title=$config{wikiname};
	my $i=0;
	my $depth=0;
	my $height=0;

	my @pagepath=(split("/", $page));
	my $pagedepth=@pagepath;
	foreach my $dir (@pagepath) {
		next if $dir eq 'index';
		$depth=$i;
		$height=($pagedepth - $depth);
		push @ret, {
			url => urlto($path, $page),
			page => $title,
			depth => $depth,
			height => $height,
			"depth_$depth" => 1,
			"height_$height" => 1,
		};
		$path.="/".$dir;
		$title=pagetitle($dir);
		$i++;
	}
	return @ret;
}

sub pagetemplate (@) {
	my %params=@_;
        my $page=$params{page};
        my $template=$params{template};

	if ($template->query(name => "parentlinks")) {
		$template->param(parentlinks => [parentlinks($page)]);
	}
}

1
