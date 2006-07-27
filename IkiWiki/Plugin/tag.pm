#!/usr/bin/perl
# Ikiwiki tag plugin.
package IkiWiki::Plugin::tag;

use warnings;
use strict;
use IkiWiki;

my %tags;

sub import { #{{{
	IkiWiki::hook(type => "preprocess", id => "tag",
		call => \&preprocess);
	IkiWiki::hook(type => "pagetemplate", id => "tag",
		call => \&pagetemplate);
} # }}}

sub preprocess (@) { #{{{
	if (! @_) {
		return "";
	}
	my %params=@_;
	my $page = $params{page};
	delete $params{page};

	$tags{$page} = [];
	foreach my $tag (keys %params) {
		push @{$tags{$page}}, $tag;
		# hidden WikiLink
		push @{$IkiWiki::links{$page}}, $tag;
	}
		
	return "";
} # }}}

sub pagetemplate ($$) { #{{{
	my $page=shift;
	my $template=shift;

	$template->param(tags => join(', ', 
			map { IkiWiki::htmllink($page, $page, $_) } 
				@{$tags{$page}}))
		if exists $tags{$page} && $template->query(name => "tags");
} # }}}

1
