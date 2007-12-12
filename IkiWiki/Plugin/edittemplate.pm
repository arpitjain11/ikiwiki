#!/usr/bin/perl
package IkiWiki::Plugin::edittemplate;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "needsbuild", id => "edittemplate",
		call => \&needsbuild);
	hook(type => "preprocess", id => "edittemplate",
		call => \&preprocess);
	hook(type => "formbuilder_setup", id => "edittemplate",
		call => \&formbuilder_setup);
} #}}}

sub needsbuild (@) { #{{{
	my $needsbuild=shift;

	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{edittemplate}) {
			if (grep { $_ eq $pagesources{$page} } @$needsbuild) {
				# remove state, it will be re-added
				# if the preprocessor directive is still
				# there during the rebuild
				delete $pagestate{$page}{edittemplate};
			}
		}
	}
} #}}}

sub preprocess (@) { #{{{
        my %params=@_;

	return "" if $params{page} ne $params{destpage};

	if (! exists $params{template} || ! length($params{template})) {
		return return "[[meta ".gettext("template not specified")."]]";
	}
	if (! exists $params{match} || ! length($params{match})) {
		return return "[[meta ".gettext("match not specified")."]]";
	}

	$pagestate{$params{page}}{edittemplate}{$params{match}}=$params{template};

	return sprintf(gettext("edittemplate %s registered for %s"),
		$params{template}, $params{match});
} # }}}

sub formbuilder_setup { #{{{
	my %params=@_;
	my $form=$params{form};
	my $page=$form->field("page");

	return if $form->title ne "editpage"
	          || $form->field("do") ne "create";

	$form->field(name => "editcontent", value => "hi mom!");
} #}}}

1
