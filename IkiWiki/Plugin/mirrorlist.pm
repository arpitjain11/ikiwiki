#!/usr/bin/perl
package IkiWiki::Plugin::mirrorlist;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "mirrorlist", call => \&getsetup);
	hook(type => "pagetemplate", id => "mirrorlist", call => \&pagetemplate);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
		mirrorlist => {
			type => "string",
			example => {},
			description => "list of mirrors",
			safe => 1,
			rebuild => 1,
		},
}

sub pagetemplate (@) {
	my %params=@_;
        my $template=$params{template};
	
	if ($template->query(name => "extrafooter")) {
		my $value=$template->param("extrafooter");
		$value.=mirrorlist($params{page});
		$template->param(extrafooter => $value);
	}
}

sub mirrorlist ($) {
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
}

1
