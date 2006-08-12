#!/usr/bin/perl
# Page inlining and blogging.
package IkiWiki::Plugin::inline;

use warnings;
use strict;
use IkiWiki;
use URI;

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
my $processing_inline=0;

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
	if (! exists $params{rss}) {
		$params{rss}="yes";
	}

	# Avoid nested inlines, to avoid loops etc.
	if ($processing_inline) {
		return "";
	}
	$processing_inline=1;

	my @list;
	foreach my $page (keys %pagesources) {
		next if $page eq $params{page};
		if (pagespec_match($page, $params{pages})) {
			push @list, $page;
		}
	}
	@list=sort { $pagectime{$b} <=> $pagectime{$a} } @list;
	if ($params{show} && @list > $params{show}) {
		@list=@list[0..$params{show} - 1];
	}

	add_depends($params{page}, $params{pages});

	my $ret="";
	
	if (exists $params{rootpage} && $config{cgiurl}) {
		# Add a blog post form, with a rss link button.
		my $formtemplate=template("blogpost.tmpl", blind_cache => 1);
		$formtemplate->param(cgiurl => $config{cgiurl});
		$formtemplate->param(rootpage => $params{rootpage});
		if ($config{rss}) {
			$formtemplate->param(rssurl => rsspage(basename($params{page})));
		}
		$ret.=$formtemplate->output;
	}
	elsif ($config{rss} && $params{rss} eq "yes") {
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
	
	foreach my $page (@list) {
		# Don't use htmllink because this way the title is separate
		# and can be overridden by other plugins.
		my $link=htmlpage(bestlink($params{page}, $page));
		$link=abs2rel($link, dirname($params{page}));
		$template->param(pageurl => $link);
		$template->param(title => pagetitle(basename($page)));
		# TODO: if $params{archive} eq "no", the only reason to do this
		# is to let the meta plugin get page title info; so stop
		# calling this next line then once the meta plugin can
		# store that accross runs.
		$template->param(content => get_inline_content($page, $params{page}));
		$template->param(ctime => displaytime($pagectime{$page}));

		run_hooks(pagetemplate => sub {
			shift->(page => $page, destpage => $params{page},
				template => $template,);
		});

		$ret.=$template->output;
		$template->clear_params;
	}
	
	# TODO: should really add this to renderedfiles and call
	# check_overwrite, but currently renderedfiles
	# only supports listing one file per page.
	if ($config{rss} && $params{rss} eq "yes") {
		writefile(rsspage($params{page}), $config{destdir},
			genrss($params{page}, @list));
		$toping{$params{page}}=1 unless $config{rebuild};
	}
	
	$processing_inline=0;

	return $ret;
} #}}}

sub get_inline_content ($$) { #{{{
	my $page=shift;
	my $destpage=shift;
	
	my $file=$pagesources{$page};
	my $type=pagetype($file);
	if (defined $type) {
		return htmlize($type, preprocess($page, $destpage, linkify($page, $destpage, readfile(srcfile($file)))));
	}
	else {
		return "";
	}
} #}}}

sub date_822 ($) { #{{{
	my $time=shift;

	eval q{use POSIX};
	my $lc_time= POSIX::setlocale(&POSIX::LC_TIME);
	POSIX::setlocale(&POSIX::LC_TIME, "C");
	my $ret=POSIX::strftime("%a, %d %b %Y %H:%M:%S %z", localtime($time));
	POSIX::setlocale(&POSIX::LC_TIME, $lc_time);
	return $ret;
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
	
	my $url=URI->new(encode_utf8("$config{url}/".htmlpage($page)));
	
	my $itemtemplate=template("rssitem.tmpl", blind_cache => 1);
	my $content="";
	foreach my $p (@pages) {
		next unless exists $renderedfiles{$p};

		my $u=URI->new(encode_utf8("$config{url}/$renderedfiles{$p}"));

		$itemtemplate->param(
			title => pagetitle(basename($p)),
			url => $u,
			permalink => $u,
			pubdate => date_822($pagectime{$p}),
			content => absolute_urls(get_inline_content($p, $page), $url),
		);
		run_hooks(pagetemplate => sub {
			shift->(page => $p, destpage => $page,
				template => $itemtemplate);
		});

		$content.=$itemtemplate->output;
		$itemtemplate->clear_params;
	}

	my $template=template("rsspage.tmpl", blind_cache => 1);
	$template->param(
		title => $config{wikiname},
		wikiname => $config{wikiname},
		pageurl => $url,
		content => $content,
	);
	run_hooks(pagetemplate => sub {
		shift->(page => $page, destpage => $page,
			template => $template);
	});
	
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
