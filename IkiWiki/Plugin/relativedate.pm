#!/usr/bin/perl
package IkiWiki::Plugin::relativedate;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	add_underlay("javascript");
	hook(type => "format", id => "relativedate", call => \&format);
} # }}}

sub getsetup () { #{{{
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
} #}}}

sub format (@) { #{{{
        my %params=@_;

	if (! ($params{content}=~s!^(<body>)!$1.include_javascript($params{page})!em)) {
		# no </body> tag, probably in preview mode
		$params{content}=include_javascript($params{page}, 1).$params{content};
	}
	return $params{content};
} # }}}

sub include_javascript ($;$) { #{{{
	my $page=shift;
	my $absolute=shift;
	
	return '<script src="'.urlto("ikiwiki.js", $page, $absolute).
		'" type="text/javascript" charset="utf-8"></script>'."\n".
		'<script src="'.urlto("relativedate.js", $page, $absolute).
		'" type="text/javascript" charset="utf-8"></script>';
} #}}}

1
