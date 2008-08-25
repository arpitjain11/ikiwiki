#!/usr/bin/perl
# Ikiwiki listdirectives plugin.
package IkiWiki::Plugin::listdirectives;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "getsetup", id => "listdirectives", call => \&getsetup);
	hook(type => "checkconfig", id => "listdirectives", call => \&checkconfig);
	hook(type => "needsbuild", id => "listdirectives", call => \&needsbuild);
	hook(type => "preprocess", id => "listdirectives", call => \&preprocess);
} # }}}

sub getsetup () { #{{{
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
		directive_description_dir => {
			type => "string",
			description => "directory in srcdir that contains PreprocessorDirective descriptions",
			example => "ikiwiki/plugin",
			safe => 1,
			rebuild => 1,
		},
} #}}}

my @fulllist;
my @earlylist;
my $pluginstring;

sub checkconfig () { #{{{
	if (! defined $config{directive_description_dir}) {
		$config{directive_description_dir} = "ikiwiki/plugin";
	}
	else {
		$config{directive_description_dir}=~s/\/+$//;
	}

	@earlylist = sort( keys %{ $IkiWiki::hooks{preprocess} } );
} #}}}

sub needsbuild (@) { #{{{
	my $needsbuild=shift;

	@fulllist = sort( keys %{ $IkiWiki::hooks{preprocess} } );
	$pluginstring = join (' ', @earlylist) . " : ". join (' ', @fulllist);

	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{listdirectives}{shown}) {
			if ($pagestate{$page}{listdirectives}{shown} ne $pluginstring) {
				push @$needsbuild, $pagesources{$page};
			}
			if (exists $pagesources{$page} &&
			    grep { $_ eq $pagesources{$page} } @$needsbuild) {
				# remove state, will be re-added if
				# the [[!listdirectives]] is still there during the
				# rebuild
				delete $pagestate{$page}{listdirectives}{shown};
			}
		}
	}
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;
	
	$pagestate{$params{destpage}}{listdirectives}{shown}=$pluginstring;
	
	my @pluginlist;
	
	if (defined $params{generated}) {
		@pluginlist = @fulllist;
	}
	else {
		@pluginlist = @earlylist;
	}
	
	my $result = '<ul class="listdirectives">';
	
	foreach my $plugin (@pluginlist) {
		$result .= '<li class="listdirectives">';
		$result .= htmllink($params{page}, $params{destpage},
			IkiWiki::linkpage($config{directive_description_dir}."/".$plugin));
		$result .= '</li>';
	}
	
	$result .= "</ul>";

	return $result;
} # }}}

1
