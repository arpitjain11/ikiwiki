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
			description => "The ikiwiki directory that contains plugin descriptions.",
			safe => 1,
			rebuild => 1,
		},
} #}}}

my @fullPluginList;
my @earlyPluginList;
my $pluginString;

sub checkconfig () { #{{{
    if (!defined $config{plugin_description_dir}) {
        $config{plugin_description_dir} = "ikiwiki/plugin/";
    }

    @earlyPluginList = sort( keys %{ $IkiWiki::hooks{preprocess} } );
} #}}}

sub needsbuild (@) { #{{{
	my $needsbuild=shift;

	@fullPluginList = sort( keys %{ $IkiWiki::hooks{preprocess} } );
	$pluginString = join (' ', @earlyPluginList) . " : ". join (' ', @fullPluginList);

	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{listpreprocessors}{shown}) {
			if ($pagestate{$page}{listpreprocessors}{shown} ne $pluginString) {
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
	
	$pagestate{$params{destpage}}{listpreprocessors}{shown}=$pluginString;
	
	my @pluginlist;
	
	if (defined $params{generated}) {
		@pluginlist = @fullPluginList;
	} else {
		@pluginlist = @earlyPluginList;
	}
	
	my $result = '<ul class="listpreprocessors">';
	
	foreach my $plugin (@pluginlist) {
		$result .= '<li class="listpreprocessors">';
		$result .= htmllink($params{page}, $params{destpage}, IkiWiki::linkpage($config{plugin_description_dir} . $plugin));
		$result .= '</li>';
	}
	
	$result .= "</ul>";

	return $result;
} # }}}

1
