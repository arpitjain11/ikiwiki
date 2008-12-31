#!/usr/bin/perl
package IkiWiki::Plugin::prettydate;
use IkiWiki 3.00;
use warnings;
no warnings 'redefine';
use strict;

sub default_timetable {
	# Blanks duplicate the time before.
	return [
		#translators: These descriptions of times of day are used
		#translators: in messages like "last edited <description>".
		#translators: %A is the name of the day of the week, while
		#translators: %A- is the name of the previous day.
		gettext("late %A- night"),			# 12
		"",						# 1
		gettext("in the wee hours of %A- night"),	# 2
		"",						# 3
		"",						# 4
		gettext("terribly early %A morning"),		# 5
		"",						# 6
		gettext("early %A morning"),			# 7
		"",						# 8
		"",						# 9
		gettext("mid-morning %A"),			# 10
		gettext("late %A morning"),			# 11
		gettext("at lunch time on %A"),			# 12
		"",						# 1
		gettext("%A afternoon"),			# 2
		"",						# 3
		"",						# 4
		gettext("late %A afternoon"),			# 5
		gettext("%A evening"),				# 6
		"",						# 7
		gettext("late %A evening"),			# 8
		"",			# 9			# 9
		gettext("%A night"),				# 10
		"",						# 11
	];
}

sub import {
	hook(type => "getsetup", id => "prettydate", call => \&getsetup);
	hook(type => "checkconfig", id => "prettydate", call => \&checkconfig);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
		prettydateformat => {
			type => "string",
			example => '%X, %B %o, %Y',
			description => "format to use to display date",
			advanced => 1,
			safe => 1,
			rebuild => 1,
		},
		timetable => {
			type => "internal",
			description => "array of time descriptions",
			safe => 1,
			rebuild => 1,
		},
}

sub checkconfig () {
	if (! defined $config{prettydateformat} ||
	    $config{prettydateformat} eq '%c') {
	    	$config{prettydateformat}='%X, %B %o, %Y';
	}

	if (! ref $config{timetable}) {
		$config{timetable}=default_timetable();
	}

	# Fill in the blanks.
	for (my $h=0; $h < 24; $h++) {
		if (! length $config{timetable}[$h]) {
			$config{timetable}[$h] = $config{timetable}[$h - 1];
		}
	}
}

sub IkiWiki::formattime ($;$) {
	my $time=shift;
	my $format=shift;
	if (! defined $format) {
		$format=$config{prettydateformat};
	}
	
	eval q{use Date::Format};
	error($@) if $@;

	my @t=localtime($time);
	my ($h, $m, $wday)=@t[2, 1, 6];
	my $t;
	if ($h == 16 && $m < 30) {
		$t = gettext("at teatime on %A");
	}
	elsif (($h == 0 && $m < 30) || ($h == 23 && $m > 50)) {
		# well, at 40 minutes it's more like the martian timeslip..
		$t = gettext("at midnight");
	}
	elsif (($h == 12 && $m < 15) || ($h == 11 && $m > 50)) {
		$t = gettext("at noon on %A");
	}
	# TODO: sunrise and sunset, but to be right I need to do it based on
	# lat and long, and calculate the appropriate one for the actual
	# time of year using Astro::Sunrise. Not tonight, it's wee hours
	# already..
	else {
		$t = $config{timetable}[$h];
		if (! length $t) {
			$t = "sometime";
		}
	}

	$t=~s{\%A-}{my @yest=@t; $yest[6]--; strftime("%A", \@yest)}eg;

	$format=~s/\%X/$t/g;
	return strftime($format, \@t);
}

1
