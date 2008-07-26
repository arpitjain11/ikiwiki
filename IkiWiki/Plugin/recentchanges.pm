#!/usr/bin/perl
package IkiWiki::Plugin::recentchanges;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "getsetup", id => "recentchanges", call => \&getsetup);
	hook(type => "checkconfig", id => "recentchanges", call => \&checkconfig);
	hook(type => "refresh", id => "recentchanges", call => \&refresh);
	hook(type => "pagetemplate", id => "recentchanges", call => \&pagetemplate);
	hook(type => "htmlize", id => "_change", call => \&htmlize);
	hook(type => "cgi", id => "recentchanges", call => \&cgi);
} #}}}

sub getsetup () { #{{{
	return
		recentchangespage => {
			type => "string",
			default => "recentchanges",
			description => "name of the recentchanges page",
			safe => 1,
			rebuild => 1,
		},
		recentchangesnum => {
			type => "integer",
			default => 100,
			description => "number of changes to track",
			safe => 1,
			rebuild => 0,
		},
} #}}}

sub checkconfig () { #{{{
	$config{recentchangespage}='recentchanges' unless defined $config{recentchangespage};
	$config{recentchangesnum}=100 unless defined $config{recentchangesnum};
} #}}}

sub refresh ($) { #{{{
	my %seen;

	# add new changes
	foreach my $change (IkiWiki::rcs_recentchanges($config{recentchangesnum})) {
		$seen{store($change, $config{recentchangespage})}=1;
	}
	
	# delete old and excess changes
	foreach my $page (keys %pagesources) {
		if ($pagesources{$page} =~ /\._change$/ && ! $seen{$page}) {
			unlink($config{srcdir}.'/'.$pagesources{$page});
		}
	}
} #}}}

# Enable the recentchanges link on wiki pages.
sub pagetemplate (@) { #{{{
	my %params=@_;
	my $template=$params{template};
	my $page=$params{page};

	if (defined $config{recentchangespage} && $config{rcs} &&
	    $page ne $config{recentchangespage} &&
	    $template->query(name => "recentchangesurl")) {
		$template->param(recentchangesurl => urlto($config{recentchangespage}, $page));
		$template->param(have_actions => 1);
	}
} #}}}

# Pages with extension _change have plain html markup, pass through.
sub htmlize (@) { #{{{
	my %params=@_;
	return $params{content};
} #}}}

sub cgi ($) { #{{{
	my $cgi=shift;
	if (defined $cgi->param('do') && $cgi->param('do') eq "recentchanges_link") {
		# This is a link from a change page to some
		# other page. Since the change pages are only generated
		# once, statically, links on them won't be updated if the
		# page they link to is deleted, or newly created, or
		# changes for whatever reason. So this CGI handles that
		# dynamic linking stuff.
		my $page=$cgi->param("page");
		if (!defined $page) {
			error("missing page parameter");
		}

		IkiWiki::loadindex();

		my $link=bestlink("", $page);
		if (! length $link) {
			print "Content-type: text/html\n\n";
			print IkiWiki::misctemplate(gettext(gettext("missing page")),
				"<p>".
				sprintf(gettext("The page %s does not exist."),
					htmllink("", "", $page)).
				"</p>");
		}
		else {
			IkiWiki::redirect($cgi, $config{url}.IkiWiki::beautify_urlpath("/".htmlpage($link)));
		}

		exit;
	}
}

sub store ($$$) { #{{{
	my $change=shift;

	my $page="$config{recentchangespage}/change_".IkiWiki::titlepage($change->{rev});

	# Optimisation to avoid re-writing pages. Assumes commits never
	# change (or that any changes are not important).
	return $page if exists $pagesources{$page} && ! $config{rebuild};

	# Limit pages to first 10, and add links to the changed pages.
	my $is_excess = exists $change->{pages}[10];
	delete @{$change->{pages}}[10 .. @{$change->{pages}}] if $is_excess;
	$change->{pages} = [
		map {
			if (length $config{cgiurl}) {
				$_->{link} = "<a href=\"".
					IkiWiki::cgiurl(
						do => "recentchanges_link",
						page => $_->{page}
					).
					"\">".
					IkiWiki::pagetitle($_->{page}).
					"</a>"
			}
			else {
				$_->{link} = IkiWiki::pagetitle($_->{page});
			}
			$_->{baseurl}="$config{url}/" if length $config{url};

			$_;
		} @{$change->{pages}}
	];
	push @{$change->{pages}}, { link => '...' } if $is_excess;

	# See if the committer is an openid.
	$change->{author}=$change->{user};
	my $oiduser=eval { IkiWiki::openiduser($change->{user}) };
	if (defined $oiduser) {
		$change->{authorurl}=$change->{user};
		$change->{user}=$oiduser;
	}
	elsif (length $config{cgiurl}) {
		$change->{authorurl} = IkiWiki::cgiurl(
			do => "recentchanges_link",
			page => (length $config{userdir} ? "$config{userdir}/" : "").$change->{author},
		);
	}

	# escape wikilinks and preprocessor stuff in commit messages
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
	IkiWiki::run_hooks(pagetemplate => sub {
		shift->(page => $page, destpage => $page,
			template => $template, rev => $change->{rev});
	});

	my $file=$page."._change";
	writefile($file, $config{srcdir}, $template->output);
	utime $change->{when}, $change->{when}, "$config{srcdir}/$file";

	return $page;
} #}}}

1
