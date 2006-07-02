#!/usr/bin/perl
# Page inlining and blogging.
package IkiWiki::Plugin::inline;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	IkiWiki::hook(type => "preprocess", id => "inline", 
		call => \&IkiWiki::preprocess_inline);
	# Hook to change to do pinging since it's called late.
	# This ensures each page only pings once and prevents slow
	# pings interrupting page builds.
	IkiWiki::hook(type => "change", id => "inline", 
		call => \&IkiWiki::pingurl);
} # }}}

# Back to ikiwiki namespace for the rest, this code is very much
# internal to ikiwiki even though it's separated into a plugin.
package IkiWiki;

my %toping;

sub preprocess_inline (@) { #{{{
	my %params=@_;

	if (! exists $params{pages}) {
		return "";
	}
	if (! exists $params{archive}) {
		$params{archive}="no";
	}
	if (! exists $params{show} && $params{archive} eq "no") {
		$params{show}=10;
	}
	add_depends($params{page}, $params{pages});

	my $ret="";
	
	if (exists $params{rootpage}) {
		# Add a blog post form, with a rss link button.
		my $formtemplate=template("blogpost.tmpl", blind_cache => 1);
		$formtemplate->param(cgiurl => $config{cgiurl});
		$formtemplate->param(rootpage => $params{rootpage});
		if ($config{rss}) {
			$formtemplate->param(rssurl => rsspage(basename($params{page})));
		}
		$ret.=$formtemplate->output;
	}
	elsif ($config{rss}) {
		# Add a rss link button.
		my $linktemplate=template("rsslink.tmpl", blind_cache => 1);
		$linktemplate->param(rssurl => rsspage(basename($params{page})));
		$ret.=$linktemplate->output;
	}
	
	my $template=template(
		(($params{archive} eq "no")
			? "inlinepage.tmpl"
			: "inlinepagetitle.tmpl"),
		blind_cache => 1,
	);
	
	my @pages;
	foreach my $page (blog_list($params{pages}, $params{show})) {
		next if $page eq $params{page};
		push @pages, $page;
		$template->param(pagelink => htmllink($params{page}, $params{page}, $page));
		$template->param(content => get_inline_content($params{page}, $page))
			if $params{archive} eq "no";
		$template->param(ctime => displaytime($pagectime{$page}));
		$ret.=$template->output;
	}
	
	# TODO: should really add this to renderedfiles and call
	# check_overwrite, but currently renderedfiles
	# only supports listing one file per page.
	if ($config{rss}) {
		writefile(rsspage($params{page}), $config{destdir},
			genrss($params{page}, @pages));
		$toping{$params{page}}=1;
	}
	
	return $ret;
} #}}}

sub blog_list ($$) { #{{{
	my $globlist=shift;
	my $maxitems=shift;

	my @list;
	foreach my $page (keys %pagesources) {
		if (globlist_match($page, $globlist)) {
			push @list, $page;
		}
	}

	@list=sort { $pagectime{$b} <=> $pagectime{$a} } @list;
	return @list if ! $maxitems || @list <= $maxitems;
	return @list[0..$maxitems - 1];
} #}}}

sub get_inline_content ($$) { #{{{
	my $parentpage=shift;
	my $page=shift;
	
	my $file=$pagesources{$page};
	my $type=pagetype($file);
	if ($type ne 'unknown') {
		return htmlize($type, preprocess($page, linkify($page, $parentpage, readfile(srcfile($file))), 1));
	}
	else {
		return "";
	}
} #}}}

sub date_822 ($) { #{{{
	my $time=shift;

	eval q{use POSIX};
	return POSIX::strftime("%a, %d %b %Y %H:%M:%S %z", localtime($time));
} #}}}

sub absolute_urls ($$) { #{{{
	# sucky sub because rss sucks
	my $content=shift;
	my $url=shift;

	$url=~s/[^\/]+$//;
	
	$content=~s/<a\s+href="(?![^:]+:\/\/)([^"]+)"/<a href="$url$1"/ig;
	$content=~s/<img\s+src="(?![^:]+:\/\/)([^"]+)"/<img src="$url$1"/ig;
	return $content;
} #}}}

sub rsspage ($) { #{{{
	my $page=shift;

	return $page.".rss";
} #}}}

sub genrss ($@) { #{{{
	my $page=shift;
	my @pages=@_;
	
	my $url="$config{url}/".htmlpage($page);
	
	my $template=template("rsspage.tmpl", blind_cache => 1);
	
	my @items;
	foreach my $p (@pages) {
		push @items, {
			itemtitle => pagetitle(basename($p)),
			itemurl => "$config{url}/$renderedfiles{$p}",
			itempubdate => date_822($pagectime{$p}),
			itemcontent => absolute_urls(get_inline_content($page, $p), $url),
		} if exists $renderedfiles{$p};
	}

	$template->param(
		title => $config{wikiname},
		pageurl => $url,
		items => \@items,
	);
	
	return $template->output;
} #}}}

sub pingurl (@) { #{{{
	return unless $config{pingurl} && %toping;

	eval q{require RPC::XML::Client};
	if ($@) {
		debug("RPC::XML::Client not found, not pinging");
		return;
	}

	foreach my $page (keys %toping) {
		my $title=pagetitle(basename($page));
		my $url="$config{url}/".htmlpage($page);
		foreach my $pingurl (@{$config{pingurl}}) {
			my $client = RPC::XML::Client->new($pingurl);
			my $req = RPC::XML::request->new('weblogUpdates.ping',
				$title, $url);
			debug("Pinging $pingurl for $page");
			my $res = $client->send_request($req);
			if (! ref $res) {
				debug("Did not receive response to ping");
			}
			my $r=$res->value;
			if (! exists $r->{flerror} || $r->{flerror}) {
				debug("Ping rejected: ".$r->{message});
			}
		}
	}
} #}}}

1
