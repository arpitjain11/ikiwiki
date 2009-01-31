#!/usr/bin/perl
package IkiWiki::Plugin::goto;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "cgi", id => 'goto',  call => \&cgi);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
		}
}

# cgi_goto(CGI, [page])
# Redirect to a specified page, or display "not found". If not specified,
# the page param from the CGI object is used.
sub cgi_goto ($;$) {
	my $q = shift;
	my $page = shift;

	if (!defined $page) {
		$page = IkiWiki::decode_utf8($q->param("page"));

		if (!defined $page) {
			error("missing page parameter");
		}
	}

	IkiWiki::loadindex();

	# If the page is internal (like a comment), see if it has a
	# permalink. Comments do.
	if (IkiWiki::isinternal($page) &&
	    defined $pagestate{$page}{meta}{permalink}) {
		redirect($q, $pagestate{$page}{meta}{permalink});
	}

	my $link = bestlink("", $page);

	if (! length $link) {
		print $q->header(-status => "404 Not Found");
		print IkiWiki::misctemplate(gettext("missing page"),
			"<p>".
			sprintf(gettext("The page %s does not exist."),
				htmllink("", "", $page)).
			"</p>".
			# Internet Explorer won't show custom 404 responses
			# unless they're >= 512 bytes
			(" " x 512));
	}
	else {
		IkiWiki::redirect($q, urlto($link, undef, 1));
	}

	exit;
}

sub cgi ($) {
	my $cgi=shift;
	my $do = $cgi->param('do');

	if (defined $do && ($do eq 'goto' || $do eq 'commenter' ||
	                       $do eq 'recentchanged_link')) {
		# goto is the preferred name for this; recentchanges_link and
		# commenter are for compatibility with any saved URLs
		cgi_goto($cgi);
	}
}

1;
