#!/usr/bin/perl
package IkiWiki::Plugin::sparkline;

use warnings;
use strict;
use IkiWiki 3.00;
use IPC::Open2;

my $match_num=qr/[-+]?[0-9]+(?:\.[0-9]+)?/;
my %locmap=(
	top => 'TEXT_TOP',
	right => 'TEXT_RIGHT',
	bottom => 'TEXT_BOTTOM',
	left => 'TEXT_LEFT',
);

sub import {
	hook(type => "getsetup", id => "sparkline", call => \&getsetup);
	hook(type => "preprocess", id => "sparkline", call => \&preprocess);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess (@) {
	my %params=@_;

	my $php;

	my $style=(exists $params{style} && $params{style} eq "bar") ? "Bar" : "Line";
	$php=qq{<?php
		require_once('sparkline/Sparkline_$style.php');
		\$sparkline = new Sparkline_$style();
		\$sparkline->SetDebugLevel(DEBUG_NONE);
	};

	foreach my $param (qw{BarWidth BarSpacing YMin YMaz}) {
		if (exists $params{lc($param)}) {
			$php.=qq{\$sparkline->Set$param(}.int($params{lc($param)}).qq{);\n};
		}
	}

	my $c=0;
	while (@_) {
		my $key=shift;
		my $value=shift;

		if ($key=~/^($match_num)(?:,($match_num))?(?:\(([a-z]+)\))?$/) {
			$c++;
			my ($x, $y);
			if (defined $2) {
				$x=$1;
				$y=$2;
			}
			else {
				$x=$c;
				$y=$1;
			}
			if ($style eq "Bar" && defined $3) {
				$php.=qq{\$sparkline->SetData($x, $y, '$3');\n};
			}
			else {
				$php.=qq{\$sparkline->SetData($x, $y);\n};
			}
		}
		elsif (! length $value) {
			error gettext("parse error")." \"$key\"";
		}
		elsif ($key eq 'featurepoint') {
			my ($x, $y, $color, $diameter, $text, $location)=
				split(/\s*,\s*/, $value);
			if (! defined $diameter || $diameter < 0) {
				error gettext("bad featurepoint diameter");
			}
			$x=int($x);
			$y=int($y);
			$color=~s/[^a-z]+//g;
			$diameter=int($diameter);
			$text=~s/[^-a-zA-Z0-9]+//g if defined $text;
			if (defined $location) {
				$location=$locmap{$location};
				if (! defined $location) {
					error gettext("bad featurepoint location");
				}
			}
			$php.=qq{\$sparkline->SetFeaturePoint($x, $y, '$color', $diameter};
			$php.=qq{, '$text'} if defined $text;
			$php.=qq{, $location} if defined $location;
			$php.=qq{);\n};
		}
	}

	if ($c eq 0) {
		error gettext("missing values");
	}

	my $height=int($params{height} || 20);
	if ($height < 2 || $height > 100) {
		error gettext("bad height value");
	}
	if ($style eq "Bar") {
		$php.=qq{\$sparkline->Render($height);\n};
	}
	else {
		if (! exists $params{width}) {
			error gettext("missing width parameter");
		}
		my $width=int($params{width});
		if ($width < 2 || $width > 1024) {
			error gettext("bad width value");
		}
		$php.=qq{\$sparkline->RenderResampled($width, $height);\n};
	}
	
	$php.=qq{\$sparkline->Output();\n?>\n};

	# Use the sha1 of the php code that generates the sparkline as
	# the base for its filename.
	eval q{use Digest::SHA1};
        error($@) if $@;
	my $fn=$params{page}."/sparkline-".
		IkiWiki::possibly_foolish_untaint(Digest::SHA1::sha1_hex($php)).
		".png";
	will_render($params{page}, $fn);

	if (! -e "$config{destdir}/$fn") {
		my $pid;
		my $sigpipe=0;
		$SIG{PIPE}=sub { $sigpipe=1 };
		$pid=open2(*IN, *OUT, "php");

		# open2 doesn't respect "use open ':utf8'"
		binmode (OUT, ':utf8');

		print OUT $php;
		close OUT;

		my $png;
		{
			local $/=undef;
			$png=<IN>;
		}
		close IN;

		waitpid $pid, 0;
		$SIG{PIPE}="DEFAULT";
		if ($sigpipe) {
			error gettext("failed to run php");
		}

		if (! $params{preview}) {
			writefile($fn, $config{destdir}, $png, 1);
		}
		else {
			# can't write the file, so embed it in a data uri
			eval q{use MIME::Base64};
		        error($@) if $@;
			return "<img src=\"data:image/png;base64,".
				encode_base64($png)."\" />";
		}
	}

	return '<img src="'.urlto($fn, $params{destpage}).'" alt="graph" />';
}

1
