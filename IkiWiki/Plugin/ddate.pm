#!/usr/bin/perl
# Discordian date support fnord ikiwiki.
package IkiWiki::Plugin::ddate;
use IkiWiki;
no warnings;

sub import { #{{{
	hook(type => "checkconfig", id => "skeleton", call => \&checkconfig);
} # }}}

sub checkconfig () { #{{{
	if (! defined $config{timeformat} ||
	    $config{timeformat} eq '%c') {
		$config{timeformat}='on %{%A, the %e of %B%}, %Y. %N%nCelebrate %H';
	}
} #}}}

sub IkiWiki::displaytime ($) { #{{{
	my $time=shift;
        eval q{use POSIX};
        my $gregorian=POSIX::strftime("%d %m %Y", localtime($time));
	my $date=`ddate +'$config{timeformat}' $gregorian`;
	chomp $date;
	if ($? || ! length $date) {
		return "some time or other (hail Eris!)";
	}
	return $date;
} #}}}

5
