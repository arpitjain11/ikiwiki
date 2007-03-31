#!/usr/bin/perl
package IkiWiki::Plugin::mirrorlist;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	hook(type => "pagetemplate", id => "mirrorlist", call => \&pagetemplate);
} # }}}

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
				$config{mirrorlist}->{$_}."/".htmlpage($page).
				qq{">$_</a>}
			} keys %{$config{mirrorlist}}
		).
		"</p>";
} # }}}

1
