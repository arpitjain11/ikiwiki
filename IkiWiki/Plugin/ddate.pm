#!/usr/bin/perl
# Discordian date support fnord ikiwiki.
package IkiWiki::Plugin::ddate;

use IkiWiki 3.00;
no warnings;

sub import {
	hook(type => "getsetup", id => "ddate", call => \&getsetup);
}

sub getsetup {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
}

sub IkiWiki::formattime ($;$) {
	my $time=shift;
	my $format=shift;
	if (! defined $format) {
		$format=$config{timeformat};
		if ($format eq '%c') {
			$format='on %A, the %e of %B, %Y. %N%nCelebrate %H';
		}
	}
	eval q{
		use DateTime;
		use DateTime::Calendar::Discordian;
	};
	if ($@) {
		 return "some time or other ($@ -- hail Eris!)";
	}
	my $dt = DateTime->from_epoch(epoch => $time);
	my $dd = DateTime::Calendar::Discordian->from_object(object => $dt);
	return $dd->strftime($format);
}

5
