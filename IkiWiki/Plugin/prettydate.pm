#!/usr/bin/perl
package IkiWiki::Plugin::prettydate;
use IkiWiki;
use warnings;
no warnings 'redefine';
use strict;

# Blanks duplicate the time before.
my $default_timetable=[
	"late at night on",	# 12
	"",			# 1
	"in the wee hours of",	# 2
	"",			# 3
	"",			# 4
	"terribly early in the morning of", # 5
	"",			# 6
	"in early morning on",	# 7
	"",			# 8
	"",			# 9
	"in mid-morning of",	# 10
	"in late morning of",	# 11
	"at lunch time on",	# 12
	"",			# 1
	"in the afternoon of",	# 2
	"",			# 3
	"",			# 4
	"in late afternoon of",	# 5
	"in the evening of",	# 6
	"",			# 7
	"in late evening on",	# 8
	"",			# 9
	"at night on",		# 10
	"",			# 11
];

sub import { #{{{
	hook(type => "checkconfig", id => "skeleton", call => \&checkconfig);
} # }}}

sub checkconfig () { #{{{
	if (! defined $config{prettydateformat} ||
	    $config{prettydateformat} eq '%c') {
	    	$config{prettydateformat}='%X %B %o, %Y';
	}

	if (! ref $config{timetable}) {
		$config{timetable}=$default_timetable;
	}

	# Fill in the blanks.
	for (my $h=0; $h < 24; $h++) {
		if (! length $config{timetable}[$h]) {
			$config{timetable}[$h] = $config{timetable}[$h - 1];
		}
	}
} #}}}

sub IkiWiki::displaytime ($) { #{{{
	my $time=shift;

	my @t=localtime($time);
	my ($h, $m)=@t[2, 1];
	if ($h == 16 && $m < 30) {
		$time = "at teatime on";
	}
	elsif (($h == 0 && $m < 30) || ($h == 23 && $m > 50)) {
		# well, at 40 minutes it's more like the martian timeslip..
		$time = "at midnight on";
	}
	elsif (($h == 12 && $m < 15) || ($h == 11 && $m > 50)) {
		$time = "at noon on";
	}
	# TODO: sunrise and sunset, but to be right I need to do it based on
	# lat and long, and calculate the appropriate one for the actual
	# time of year using Astro::Sunrise. Not tonight, it's wee hours
	# already..
	else {
		$time = $config{timetable}[$h];
		if (! length $time) {
			$time = "sometime";
		}
	}

	eval q{use Date::Format};
	error($@) if $@;
	my $format=$config{prettydateformat};
	$format=~s/\%X/$time/g;
	return strftime($format, \@t);
} #}}}

1
