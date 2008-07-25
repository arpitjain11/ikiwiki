#!/usr/bin/perl
package IkiWiki::Plugin::mirrorlist;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "getsetup", id => "mirrorlist", call => \&getsetup);
	hook(type => "pagetemplate", id => "mirrorlist", call => \&pagetemplate);
} # }}}

sub getsetup () { #{{{
	return
		mirrorlist => {
			type => "string",
			default => "",
			description => "list of mirrors",
			safe => 1,
			rebuild => 1,
		},
} #}}}

sub pagetemplate (@) { #{{{
	my %params=@_;
        my $template=$params{template};
	
	$template->param(extrafooter => mirrorlist($params{page}))
		if $template->query(name => "extrafooter");
} # }}}

sub mirrorlist ($) { #{{{
	my $page=shift;
	return "<p>".
		(keys %{$config{mirrorlist}} > 1 ? gettext("Mirrors") : gettext("Mirror")).
		": ".
		join(", ",
			map { 
				qq{<a href="}.
				$config{mirrorlist}->{$_}."/".urlto($page, "").
				qq{">$_</a>}
			} keys %{$config{mirrorlist}}
		).
		"</p>";
} # }}}

1
