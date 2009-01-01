#! /usr/bin/perl
# Copyright (c) 2006, 2007 Manoj Srivastava <srivasta@debian.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

require 5.002;
package IkiWiki::Plugin::calendar;

use warnings;
use strict;
use IkiWiki 3.00;
use Time::Local;
use POSIX;

my %cache;
my %linkcache;
my $time=time;
my @now=localtime($time);

sub import {
	hook(type => "getsetup", id => "calendar", call => \&getsetup);
	hook(type => "needsbuild", id => "calendar", call => \&needsbuild);
	hook(type => "preprocess", id => "calendar", call => \&preprocess);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
		archivebase => {
			type => "string",
			example => "archives",
			description => "base of the archives hierarchy",
			safe => 1,
			rebuild => 1,
		},
}

sub is_leap_year (@) {
	my %params=@_;
	return ($params{year} % 4 == 0 && (($params{year} % 100 != 0) || $params{year} % 400 == 0));
}

sub month_days {
	my %params=@_;
	my $days_in_month = (31,28,31,30,31,30,31,31,30,31,30,31)[$params{month}-1];
	if ($params{month} == 2 && is_leap_year(%params)) {
		$days_in_month++;
	}
	return $days_in_month;
}

sub format_month (@) {
	my %params=@_;

	my $pagespec = $params{pages};
	my $year     = $params{year};
	my $month    = $params{month};
	my $pmonth   = $params{pmonth};
	my $nmonth   = $params{nmonth};
	my $pyear    = $params{pyear};
	my $nyear    = $params{nyear};

	my @list;
	my $calendar="\n";

	# When did this month start?
	my @monthstart = localtime(timelocal(0,0,0,1,$month-1,$year-1900));

	my $future_dom = 0;
	my $today      = 0;
	if ($year == $now[5]+1900 && $month == $now[4]+1) {
		$future_dom = $now[3]+1;
		$today      = $now[3];
	}

	# Find out month names for this, next, and previous months
	my $monthname=POSIX::strftime("%B", @monthstart);
	my $pmonthname=POSIX::strftime("%B", localtime(timelocal(0,0,0,1,$pmonth-1,$pyear-1900)));
	my $nmonthname=POSIX::strftime("%B", localtime(timelocal(0,0,0,1,$nmonth-1,$nyear-1900)));

	my $archivebase = 'archives';
	$archivebase = $config{archivebase} if defined $config{archivebase};
	$archivebase = $params{archivebase} if defined $params{archivebase};
  
	# Calculate URL's for monthly archives.
	my ($url, $purl, $nurl)=("$monthname",'','');
	if (exists $cache{$pagespec}{"$year/$month"}) {
		$url = htmllink($params{page}, $params{destpage}, 
			"$archivebase/$year/".sprintf("%02d", $month),
			linktext => " $monthname ");
	}
	add_depends($params{page}, "$archivebase/$year/".sprintf("%02d", $month));
	if (exists $cache{$pagespec}{"$pyear/$pmonth"}) {
		$purl = htmllink($params{page}, $params{destpage}, 
			"$archivebase/$pyear/" . sprintf("%02d", $pmonth),
			linktext => " $pmonthname ");
	}
	add_depends($params{page}, "$archivebase/$pyear/".sprintf("%02d", $pmonth));
	if (exists $cache{$pagespec}{"$nyear/$nmonth"}) {
		$nurl = htmllink($params{page}, $params{destpage}, 
			"$archivebase/$nyear/" . sprintf("%02d", $nmonth),
			linktext => " $nmonthname ");
	}
	add_depends($params{page}, "$archivebase/$nyear/".sprintf("%02d", $nmonth));

	# Start producing the month calendar
	$calendar=<<EOF;
<table class="month-calendar">
	<caption class="month-calendar-head">
	$purl
	$url
	$nurl
	</caption>
	<tr>
EOF

	# Suppose we want to start the week with day $week_start_day
	# If $monthstart[6] == 1
	my $week_start_day = $params{week_start_day};

	my $start_day = 1 + (7 - $monthstart[6] + $week_start_day) % 7;
	my %downame;
	my %dowabbr;
	for my $dow ($week_start_day..$week_start_day+6) {
		my @day=localtime(timelocal(0,0,0,$start_day++,$month-1,$year-1900));
		my $downame = POSIX::strftime("%A", @day);
		my $dowabbr = POSIX::strftime("%a", @day);
		$downame{$dow % 7}=$downame;
		$dowabbr{$dow % 7}=$dowabbr;
		$calendar.= qq{\t\t<th class="month-calendar-day-head $downame">$dowabbr</th>\n};
	}

	$calendar.=<<EOF;
	</tr>
EOF

	my $wday;
	# we start with a week_start_day, and skip until we get to the first
	for ($wday=$week_start_day; $wday != $monthstart[6]; $wday++, $wday %= 7) {
		$calendar.=qq{\t<tr>\n} if $wday == $week_start_day;
		$calendar.=qq{\t\t<td class="month-calendar-day-noday $downame{$wday}">&nbsp;</td>\n};
	}

	# At this point, either the first is a week_start_day, in which case
	# nothing has been printed, or else we are in the middle of a row.
	for (my $day = 1; $day <= month_days(year => $year, month => $month);
	     $day++, $wday++, $wday %= 7) {
		# At tihs point, on a week_start_day, we close out a row,
		# and start a new one -- unless it is week_start_day on the
		# first, where we do not close a row -- since none was started.
		if ($wday == $week_start_day) {
			$calendar.=qq{\t</tr>\n} unless $day == 1;
			$calendar.=qq{\t<tr>\n};
		}
		
		my $tag;
		my $mtag = sprintf("%02d", $month);
		if (defined $cache{$pagespec}{"$year/$mtag/$day"}) {
			if ($day == $today) {
				$tag='month-calendar-day-this-day';
			}
			else {
				$tag='month-calendar-day-link';
			}
			$calendar.=qq{\t\t<td class="$tag $downame{$wday}">};
			$calendar.=htmllink($params{page}, $params{destpage}, 
			                    pagename($linkcache{"$year/$mtag/$day"}),
			                    "linktext" => "$day");
			push @list, pagename($linkcache{"$year/$mtag/$day"});
			$calendar.=qq{</td>\n};
		}
		else {
			if ($day == $today) {
				$tag='month-calendar-day-this-day';
			}
			elsif ($day == $future_dom) {
				$tag='month-calendar-day-future';
			}
			else {
				$tag='month-calendar-day-nolink';
			}
			$calendar.=qq{\t\t<td class="$tag $downame{$wday}">$day</td>\n};
		}
	}

	# finish off the week
	for (; $wday != $week_start_day; $wday++, $wday %= 7) {
		$calendar.=qq{\t\t<td class="month-calendar-day-noday $downame{$wday}">&nbsp;</td>\n};
	}
	$calendar.=<<EOF;
	</tr>
</table>
EOF

	# Add dependencies to update the calendar whenever pages
	# matching the pagespec are added or removed.
	add_depends($params{page}, $params{pages});
	# Explicitly add all currently linked pages as dependencies, so
        # that if they are removed, the calendar will be sure to be updated.
        add_depends($params{page}, join(" or ", @list));

	return $calendar;
}

sub format_year (@) {
	my %params=@_;

	my $pagespec = $params{pages};
	my $year     = $params{year};
	my $month    = $params{month};
	my $pmonth   = $params{pmonth};
	my $nmonth   = $params{nmonth};
	my $pyear    = $params{pyear};
	my $nyear    = $params{nyear};

	my $calendar="\n";

	my $future_month = 0;
	$future_month = $now[4]+1 if ($year == $now[5]+1900);

	my $archivebase = 'archives';
	$archivebase = $config{archivebase} if defined $config{archivebase};
	$archivebase = $params{archivebase} if defined $params{archivebase};

	# calculate URL's for previous and next years
	my ($url, $purl, $nurl)=("$year",'','');
	if (exists $cache{$pagespec}{"$year"}) {
		$url = htmllink($params{page}, $params{destpage}, 
			"$archivebase/$year",
			linktext => "$year");
	}
	add_depends($params{page}, "$archivebase/$year");
	if (exists $cache{$pagespec}{"$pyear"}) {
		$purl = htmllink($params{page}, $params{destpage}, 
			"$archivebase/$pyear",
			linktext => "\&larr;");
	}
	add_depends($params{page}, "$archivebase/$pyear");
	if (exists $cache{$pagespec}{"$nyear"}) {
		$nurl = htmllink($params{page}, $params{destpage}, 
			"$archivebase/$nyear",
			linktext => "\&rarr;");
	}
	add_depends($params{page}, "$archivebase/$nyear");

	# Start producing the year calendar
	$calendar=<<EOF;
<table class="year-calendar">
	<caption class="year-calendar-head">
	$purl
	$url
	$nurl
	</caption>
	<tr>
		<th class="year-calendar-subhead" colspan="$params{months_per_row}">Months</th>
	</tr>
EOF

	for ($month = 1; $month <= 12; $month++) {
		my @day=localtime(timelocal(0,0,0,15,$month-1,$year-1900));
		my $murl;
		my $monthname = POSIX::strftime("%B", @day);
		my $monthabbr = POSIX::strftime("%b", @day);
		$calendar.=qq{\t<tr>\n}  if ($month % $params{months_per_row} == 1);
		my $tag;
		my $mtag=sprintf("%02d", $month);
		if ($month == $params{month}) {
			if ($cache{$pagespec}{"$year/$mtag"}) {
				$tag = 'this_month_link';
			}
			else {
				$tag = 'this_month_nolink';
			}
		}
		elsif ($cache{$pagespec}{"$year/$mtag"}) {
			$tag = 'month_link';
		} 
		elsif ($future_month && $month >= $future_month) {
			$tag = 'month_future';
		} 
		else {
			$tag = 'month_nolink';
		}

		if ($cache{$pagespec}{"$year/$mtag"}) {
			$murl = htmllink($params{page}, $params{destpage}, 
				"$archivebase/$year/$mtag",
				linktext => "$monthabbr");
			$calendar.=qq{\t<td class="$tag">};
			$calendar.=$murl;
			$calendar.=qq{\t</td>\n};
		}
		else {
			$calendar.=qq{\t<td class="$tag">$monthabbr</td>\n};
		}
		add_depends($params{page}, "$archivebase/$year/$mtag");

		$calendar.=qq{\t</tr>\n} if ($month % $params{months_per_row} == 0);
	}

	$calendar.=<<EOF;
</table>
EOF

	return $calendar;
}

sub preprocess (@) {
	my %params=@_;
	$params{pages} = "*"            unless defined $params{pages};
	$params{type}  = "month"        unless defined $params{type};
	$params{month} = sprintf("%02d", $params{month}) if defined  $params{month};
	$params{week_start_day} = 0     unless defined $params{week_start_day};
	$params{months_per_row} = 3     unless defined $params{months_per_row};

	if (! defined $params{year} || ! defined $params{month}) {
		# Record that the calendar next changes at midnight.
		$pagestate{$params{destpage}}{calendar}{nextchange}=($time
			+ (60 - $now[0])		# seconds
			+ (59 - $now[1]) * 60		# minutes
			+ (23 - $now[2]) * 60 * 60	# hours
		);
		
		$params{year}  = 1900 + $now[5] unless defined $params{year};
		$params{month} = 1    + $now[4] unless defined $params{month};
	}
	else {
		delete $pagestate{$params{destpage}}{calendar};
	}

	# Calculate month names for next month, and previous months
	my $pmonth = $params{month} - 1;
	my $nmonth = $params{month} + 1;
	my $pyear  = $params{year}  - 1;
	my $nyear  = $params{year}  + 1;

	# Adjust for January and December
	if ($params{month} == 1) {
		$pmonth = 12;
		$pyear--;
	}
	if ($params{month} == 12) {
		$nmonth = 1;
		$nyear++;
	}

	$params{pmonth}=$pmonth;
	$params{nmonth}=$nmonth;
	$params{pyear} =$pyear;
	$params{nyear} =$nyear;

	my $calendar="\n";
	my $pagespec=$params{pages};
	my $page =$params{page};

	if (! defined $cache{$pagespec}) {
		foreach my $p (keys %pagesources) {
			next unless pagespec_match($p, $pagespec);
			my $mtime = $IkiWiki::pagectime{$p};
			my $src   = $pagesources{$p};
			my @date  = localtime($mtime);
			my $mday  = $date[3];
			my $month = $date[4] + 1;
			my $year  = $date[5] + 1900;
			my $mtag  = sprintf("%02d", $month);

			# Only one posting per day is being linked to.
			$linkcache{"$year/$mtag/$mday"} = "$src";
			$cache{$pagespec}{"$year"}++;
			$cache{$pagespec}{"$year/$mtag"}++;
			$cache{$pagespec}{"$year/$mtag/$mday"}++;
		}
	}

	if ($params{type} =~ /month/i) {
		$calendar=format_month(%params);
	}
	elsif ($params{type} =~ /year/i) {
		$calendar=format_year(%params);
	}

	return "\n<div><div class=\"calendar\">$calendar</div></div>\n";
} #}}

sub needsbuild (@) {
	my $needsbuild=shift;
	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{calendar}{nextchange}) {
			if ($pagestate{$page}{calendar}{nextchange} <= $time) {
				# force a rebuild so the calendar shows
				# the current day
				push @$needsbuild, $pagesources{$page};
			}
			if (exists $pagesources{$page} && 
			    grep { $_ eq $pagesources{$page} } @$needsbuild) {
				# remove state, will be re-added if
				# the calendar is still there during the
				# rebuild
				delete $pagestate{$page}{calendar};
			}
		}
	}
}

1
