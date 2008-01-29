#!/usr/bin/perl
package IkiWiki::Plugin::recentchanges;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "checkconfig", id => "recentchanges",
		call => \&checkconfig);
	hook(type => "needsbuild", id => "recentchanges",
		call => \&needsbuild);
	hook(type => "preprocess", id => "recentchanges",
		call => \&preprocess);
	hook(type => "htmlize", id => "_change",
		call => \&htmlize);
} #}}}

sub checkconfig () { #{{{
	my @changes=IkiWiki::rcs_recentchanges(100);
	updatechanges("*", "recentchanges", \@changes);
} #}}}

sub needsbuild () { #{{{
	# TODO
} #}}}

sub preprocess (@) { #{{{
	my %params=@_;

	# TODO

	return "";
} #}}}

# Pages with extension _change have plain html markup, pass through.
sub htmlize (@) { #{{{
	my %params=@_;
	return $params{content};
} #}}}

sub store ($$) { #{{{
	my $change=shift;
	my $subdir=shift;
	
	my $page="$subdir/change_".IkiWiki::titlepage($change->{rev});

	# Optimisation to avoid re-writing pages. Assumes commits never
	# change (or that any changes are not important).
	return if exists $pagesources{$page} && ! $config{rebuild};

	# Limit pages to first 10, and add links to the changed pages.
	my $is_excess = exists $change->{pages}[10];
	delete @{$change->{pages}}[10 .. @{$change->{pages}}] if $is_excess;
	$change->{pages} = [
		map {
			if (length $config{url}) {
				$_->{link} = "<a href=\"$config{url}/".
					urlto($_->{page},"")."\">".
					IkiWiki::pagetitle($_->{page})."</a>";
			}
			else {
				$_->{link} = IkiWiki::pagetitle($_->{page});
			}
			$_;
		} @{$change->{pages}}
	];
	push @{$change->{pages}}, { link => '...' } if $is_excess;

	# Take the first line of the commit message as a summary.
	my $m=shift @{$change->{message}};
	$change->{summary}=$m->{line};

	# See if the committer is an openid.
	my $oiduser=IkiWiki::openiduser($change->{user});
	if (defined $oiduser) {
		$change->{authorurl}=$change->{user};
		$change->{user}=$oiduser;
	}
	elsif (length $config{url}) {
		$change->{authorurl}="$config{url}/".
			(length $config{userdir} ? "$config{userdir}/" : "").
			$change->{user};
	}

	# Fill out a template with the change info.
	my $template=template("change.tmpl", blind_cache => 1);
	$template->param(%$change);
	$template->param(baseurl => "$config{url}/") if length $config{url};
	IkiWiki::run_hooks(pagetemplate => sub {
		shift->(page => $page, destpage => $page, template => $template);
	});

	writefile($page."._change", $config{srcdir}, $template->output);
	utime $change->{when}, $change->{when}, "$config{srcdir}/$page._change";
} #}}}

sub updatechanges ($$) { #{{{
	my $pagespec=shift;
	my $subdir=shift;
	my @changes=@{shift()};
	foreach my $change (@changes) {
		store($change, $subdir);
	}
	# TODO: delete old
} #}}}

1
