#!/usr/bin/perl
# Discordian date support fnord ikiwiki.
package IkiWiki::Plugin::ddate;
use IkiWiki;
use IkiWiki::Render; # so we can redefine it here
no warnings;

sub import { #{{{
	IkiWiki::hook(type => "checkconfig", id => "skeleton", 
		call => \&checkconfig);
} # }}}

sub checkconfig () { #{{{
	if (! defined $IkiWiki::config{timeformat} ||
	    $IkiWiki::config{timeformat} eq '%c') {
		$IkiWiki::config{timeformat}='on %{%A, the %e of %B%}, %Y. %N%nCelebrate %H';
	}
} #}}}

sub IkiWiki::displaytime ($) { #{{{
	my $time=shift;
        eval q{use POSIX};
        my $gregorian=POSIX::strftime("%d %m %Y", localtime($time));
	my $date=`ddate +'$IkiWiki::config{timeformat}' $gregorian`;
	chomp $date;
	if ($? || ! length $date) {
		return "some time or other (hail Eris!)";
	}
	return $date;
} #}}}

5
