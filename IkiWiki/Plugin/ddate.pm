#!/usr/bin/perl
# Discordian date support fnord ikiwiki.
package IkiWiki::Plugin::ddate;

use IkiWiki 2.00;
no warnings;

sub import { #{{{
	hook(type => "checkconfig", id => "ddate", call => \&checkconfig);
} # }}}

sub checkconfig () { #{{{
	if (! defined $config{timeformat} ||
	    $config{timeformat} eq '%c') {
		$config{timeformat}='on %A, the %e of %B, %Y. %N%nCelebrate %H';
	}
} #}}}

sub IkiWiki::displaytime ($;$) { #{{{
	my $time=shift;
	eval q{
		use DateTime;
		use DateTime::Calendar::Discordian;
	};
	if ($@) {
		 return "some time or other ($@ -- hail Eris!)";
	}
	my $dt = DateTime->from_epoch(epoch => $time);
	my $dd = DateTime::Calendar::Discordian->from_object(object => $dt);
	return $dd->strftime($IkiWiki::config{timeformat});
} #}}}

5
