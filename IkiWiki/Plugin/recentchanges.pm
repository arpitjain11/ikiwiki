#!/usr/bin/perl
package IkiWiki::Plugin::recentchanges;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "needsbuild", id => "recentchanges",
		call => \&needsbuild);
	hook(type => "preprocess", id => "recentchanges",
		call => \&preprocess);
	hook(type => "htmlize", id => "_change",
		call => \&htmlize);
} #}}}

sub needsbuild ($) { #{{{
	my $needsbuild=shift;
	my @changes=IkiWiki::rcs_recentchanges(100);
	push @$needsbuild, updatechanges("*", "recentchanges", \@changes);
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

	# escape  wikilinks and preprocessor stuff in commit messages
	if (ref $change->{message}) {
		foreach my $field (@{$change->{message}}) {
			if (exists $field->{line}) {
				$field->{line} =~ s/(?<!\\)\[\[/\\\[\[/g;
			}
		}
	}

	# Fill out a template with the change info.
	my $template=template("change.tmpl", blind_cache => 1);
	$template->param(
		%$change,
		commitdate => displaytime($change->{when}, "%X %x"),
		wikiname => $config{wikiname},
	);
	$template->param(baseurl => "$config{url}/") if length $config{url};
	IkiWiki::run_hooks(pagetemplate => sub {
		shift->(page => $page, destpage => $page, template => $template);
	});

	my $file=$page."._change";
	writefile($file, $config{srcdir}, $template->output);
	utime $change->{when}, $change->{when}, "$config{srcdir}/$file";
	return $file;
} #}}}

sub updatechanges ($$) { #{{{
	my $pagespec=shift;
	my $subdir=shift;
	my @changes=@{shift()};
	my @ret;
	foreach my $change (@changes) {
		my $file=store($change, $subdir);
		push @ret, $file if defined $file;
	}
	# TODO: delete old
	
	return @ret;
} #}}}

1