#!/usr/bin/perl
# Ikiwiki listpreprocessors plugin.
package IkiWiki::Plugin::listpreprocessors;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "getsetup", id => "listpreprocessors", call => \&getsetup);
	hook(type => "checkconfig", id => "listpreprocessors", call => \&checkconfig);
	hook(type => "needsbuild", id => "listpreprocessors", call => \&needsbuild);
	hook(type => "preprocess", id => "listpreprocessors", call => \&preprocess);
} # }}}

sub getsetup () { #{{{
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
		preprocessor_description_dir => {
			type => "string",
			description => "directory in srcdir that contains preprocessor descriptions",
			example => "ikiwiki/plugin",
			safe => 1,
			rebuild => 1,
		},
} #}}}

my @fulllist;
my @earlylist;
my $pluginstring;

sub checkconfig () { #{{{
	if (! defined $config{preprocessor_description_dir}) {
		$config{preprocessor_description_dir} = "ikiwiki/plugin";
	}
	else {
		$config{preprocessor_description_dir}=~s/\/+$//;
	}

	@earlylist = sort( keys %{ $IkiWiki::hooks{preprocess} } );
} #}}}

sub needsbuild (@) { #{{{
	my $needsbuild=shift;

	@fulllist = sort( keys %{ $IkiWiki::hooks{preprocess} } );
	$pluginstring = join (' ', @earlylist) . " : ". join (' ', @fulllist);

	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{listpreprocessors}{shown}) {
			if ($pagestate{$page}{listpreprocessors}{shown} ne $pluginstring) {
				push @$needsbuild, $pagesources{$page};
			}
			if (exists $pagesources{$page} &&
			    grep { $_ eq $pagesources{$page} } @$needsbuild) {
				# remove state, will be re-added if
				# the [[!listpreprocessors]] is still there during the
				# rebuild
				delete $pagestate{$page}{listpreprocessors}{shown};
			}
		}
	}
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;
	
	$pagestate{$params{destpage}}{listpreprocessors}{shown}=$pluginstring;
	
	my @pluginlist;
	
	if (defined $params{generated}) {
		@pluginlist = @fulllist;
	}
	else {
		@pluginlist = @earlylist;
	}
	
	my $result = '<ul class="listpreprocessors">';
	
	foreach my $plugin (@pluginlist) {
		$result .= '<li class="listpreprocessors">';
		$result .= htmllink($params{page}, $params{destpage},
			IkiWiki::linkpage($config{preprocessor_description_dir}."/".$plugin));
		$result .= '</li>';
	}
	
	$result .= "</ul>";

	return $result;
} # }}}

1
