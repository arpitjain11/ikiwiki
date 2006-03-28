package IkiWiki;

use warnings;
use strict;
use File::Spec;

sub linkify ($$) { #{{{
	my $content=shift;
	my $page=shift;

	$content =~ s{(\\?)$config{wiki_link_regexp}}{
		$2 ? ( $1 ? "[[$2|$3]]" : htmllink($page, $3, 0, 0, pagetitle($2)))
		   : ( $1 ? "[[$3]]" :    htmllink($page, $3))
	}eg;
	
	return $content;
} #}}}

sub htmlize ($$) { #{{{
	my $type=shift;
	my $content=shift;
	
	if (! $INC{"/usr/bin/markdown"}) {
		no warnings 'once';
		$blosxom::version="is a proper perl module too much to ask?";
		use warnings 'all';
		do "/usr/bin/markdown";
	}
	
	if ($type eq '.mdwn') {
		return Markdown::Markdown($content);
	}
	else {
		error("htmlization of $type not supported");
	}
} #}}}

sub backlinks ($) { #{{{
	my $page=shift;

	my @links;
	foreach my $p (keys %links) {
		next if bestlink($page, $p) eq $page;
		if (grep { length $_ && bestlink($p, $_) eq $page } @{$links{$p}}) {
			my $href=File::Spec->abs2rel(htmlpage($p), dirname($page));
			
			# Trim common dir prefixes from both pages.
			my $p_trimmed=$p;
			my $page_trimmed=$page;
			my $dir;
			1 while (($dir)=$page_trimmed=~m!^([^/]+/)!) &&
			        defined $dir &&
			        $p_trimmed=~s/^\Q$dir\E// &&
			        $page_trimmed=~s/^\Q$dir\E//;
				       
			push @links, { url => $href, page => $p_trimmed };
		}
	}

	return sort { $a->{page} cmp $b->{page} } @links;
} #}}}

sub parentlinks ($) { #{{{
	my $page=shift;
	
	my @ret;
	my $pagelink="";
	my $path="";
	my $skip=1;
	foreach my $dir (reverse split("/", $page)) {
		if (! $skip) {
			$path.="../";
			unshift @ret, { url => "$path$dir.html", page => $dir };
		}
		else {
			$skip=0;
		}
	}
	unshift @ret, { url => length $path ? $path : ".", page => $config{wikiname} };
	return @ret;
} #}}}

sub rsspage ($) { #{{{
	my $page=shift;

	return $page.".rss";
} #}}}

sub postprocess { #{{{
	# Takes content to postprocess followed by a list of postprocessor
	# commands and subroutine references to run for the commands.
	my $page=shift;
	my $content=shift;
	my %commands=@_;
	
	my $handle=sub {
		my $escape=shift;
		my $command=shift;
		my $params=shift;
		if (length $escape) {
			"[[$command $params]]";
		}
		elsif (exists $commands{$command}) {
			my %params;
			while ($params =~ /(\w+)=\"([^"]+)"(\s+|$)/g) {
				$params{$1}=$2;
			}
			$commands{$command}->($page, %params);
		}
		else {
			"[[bad directive $command]]";
		}
	};
	
	$content =~ s{(\\?)$config{wiki_processor_regexp}}{$handle->($1, $2, $3)}eg;
	return $content;
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
		return htmlize($type, linkify(readfile("$config{srcdir}/$file"), $parentpage));
	}
	else {
		return "";
	}
} #}}}

sub postprocess_html_inline { #{{{
	my $parentpage=shift;
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
	$inlinepages{$parentpage}=$params{pages};
	
	my $ret="";
	
	if (exists $params{rootpage}) {
		my $formtemplate=HTML::Template->new(blind_cache => 1,
			filename => "$config{templatedir}/blogpost.tmpl");
		$formtemplate->param(cgiurl => $config{cgiurl});
		$formtemplate->param(rootpage => $params{rootpage});
		my $form=$formtemplate->output;
		$ret.=$form;
	}
	
	my $template=HTML::Template->new(blind_cache => 1,
		filename => (($params{archive} eq "no") 
				? "$config{templatedir}/inlinepage.tmpl"
				: "$config{templatedir}/inlinepagetitle.tmpl"));
	
	foreach my $page (blog_list($params{pages}, $params{show})) {
		next if $page eq $parentpage;
		$template->param(pagelink => htmllink($parentpage, $page));
		$template->param(content => get_inline_content($parentpage, $page))
			if $params{archive} eq "no";
		$template->param(ctime => scalar(gmtime($pagectime{$page})));
		$ret.=$template->output;
	}
	
	return $ret;
} #}}}

sub genpage ($$$) { #{{{
	my $content=shift;
	my $page=shift;
	my $mtime=shift;

	$content = postprocess($page, $content, inline => \&postprocess_html_inline);
	
	my $title=pagetitle(basename($page));
	
	my $template=HTML::Template->new(blind_cache => 1,
		filename => "$config{templatedir}/page.tmpl");
	
	if (length $config{cgiurl}) {
		$template->param(editurl => "$config{cgiurl}?do=edit&page=$page");
		$template->param(prefsurl => "$config{cgiurl}?do=prefs");
		if ($config{rcs}) {
			$template->param(recentchangesurl => "$config{cgiurl}?do=recentchanges");
		}
	}

	if (length $config{historyurl}) {
		my $u=$config{historyurl};
		$u=~s/\[\[file\]\]/$pagesources{$page}/g;
		$template->param(historyurl => $u);
	}

	if ($config{rss} && $inlinepages{$page}) {
		$template->param(rssurl => rsspage(basename($page)));
	}
	
	$template->param(
		title => $title,
		wikiname => $config{wikiname},
		parentlinks => [parentlinks($page)],
		content => $content,
		backlinks => [backlinks($page)],
		discussionlink => htmllink($page, "Discussion", 1, 1),
		mtime => scalar(gmtime($mtime)),
	);
	
	return $template->output;
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
	
	$content=~s/<a\s+href="(?!http:\/\/)([^"]+)"/<a href="$url$1"/ig;
	$content=~s/<img\s+src="(?!http:\/\/)([^"]+)"/<img src="$url$1"/ig;
	return $content;
} #}}}

sub genrss ($$$) { #{{{
	my $content=shift;
	my $page=shift;
	my $mtime=shift;
	
	my $url="$config{url}/".htmlpage($page);
	
	my $template=HTML::Template->new(blind_cache => 1,
		filename => "$config{templatedir}/rsspage.tmpl");
	
	my @items;
	my $isblog=0;
	my $gen_blog=sub {
		my $parentpage=shift;
		my %params=@_;
		
		if (! exists $params{show}) {
			$params{show}=10;
		}
		if (! exists $params{pages}) {
			return "";
		}
		
		$isblog=1;
		foreach my $page (blog_list($params{pages}, $params{show})) {
			next if $page eq $parentpage;
			push @items, {
				itemtitle => pagetitle(basename($page)),
				itemurl => "$config{url}/$renderedfiles{$page}",
				itempubdate => date_822($pagectime{$page}),
				itemcontent => absolute_urls(get_inline_content($parentpage, $page), $url),
			} if exists $renderedfiles{$page};
		}
		
		return "";
	};
	
	$content = postprocess($page, $content, inline => $gen_blog);

	$template->param(
		title => $config{wikiname},
		pageurl => $url,
		items => \@items,
	);
	
	return $template->output;
} #}}}

sub check_overwrite ($$) { #{{{
	# Important security check. Make sure to call this before saving
	# any files to the source directory.
	my $dest=shift;
	my $src=shift;
	
	if (! exists $renderedfiles{$src} && -e $dest && ! $config{rebuild}) {
		error("$dest already exists and was rendered from ".
			join(" ",(grep { $renderedfiles{$_} eq $dest } keys
				%renderedfiles)).
			", before, so not rendering from $src");
	}
} #}}}

sub mtime ($) { #{{{
	my $file=shift;
	
	return (stat($file))[9];
} #}}}

sub findlinks ($$) { #{{{
	my $content=shift;
	my $page=shift;

	my @links;
	while ($content =~ /(?<!\\)$config{wiki_link_regexp}/g) {
		push @links, lc($2);
	}
	# Discussion links are a special case since they're not in the text
	# of the page, but on its template.
	return @links, "$page/discussion";
} #}}}

sub render ($) { #{{{
	my $file=shift;
	
	my $type=pagetype($file);
	my $content=readfile("$config{srcdir}/$file");
	if ($type ne 'unknown') {
		my $page=pagename($file);
		
		$links{$page}=[findlinks($content, $page)];
		delete $inlinepages{$page};
		
		$content=linkify($content, $page);
		$content=htmlize($type, $content);
		
		check_overwrite("$config{destdir}/".htmlpage($page), $page);
		writefile("$config{destdir}/".htmlpage($page),
			genpage($content, $page, mtime("$config{srcdir}/$file")));
		$oldpagemtime{$page}=time;
		$renderedfiles{$page}=htmlpage($page);

		# TODO: should really add this to renderedfiles and call
		# check_overwrite, as above, but currently renderedfiles
		# only supports listing one file per page.
		if ($config{rss} && exists $inlinepages{$page}) {
			writefile("$config{destdir}/".rsspage($page),
				genrss($content, $page, mtime("$config{srcdir}/$file")));
		}
	}
	else {
		$links{$file}=[];
		check_overwrite("$config{destdir}/$file", $file);
		writefile("$config{destdir}/$file", $content);
		$oldpagemtime{$file}=time;
		$renderedfiles{$file}=$file;
	}
} #}}}

sub prune ($) { #{{{
	my $file=shift;

	unlink($file);
	my $dir=dirname($file);
	while (rmdir($dir)) {
		$dir=dirname($dir);
	}
} #}}}

sub refresh () { #{{{
	# find existing pages
	my %exists;
	my @files;
	eval q{use File::Find};
	find({
		no_chdir => 1,
		wanted => sub {
			if (/$config{wiki_file_prune_regexp}/) {
				no warnings 'once';
				$File::Find::prune=1;
				use warnings "all";
			}
			elsif (! -d $_ && ! -l $_) {
				my ($f)=/$config{wiki_file_regexp}/; # untaint
				if (! defined $f) {
					warn("skipping bad filename $_\n");
				}
				else {
					$f=~s/^\Q$config{srcdir}\E\/?//;
					push @files, $f;
					$exists{pagename($f)}=1;
				}
			}
		},
	}, $config{srcdir});

	my %rendered;

	# check for added or removed pages
	my @add;
	foreach my $file (@files) {
		my $page=pagename($file);
		if (! $oldpagemtime{$page}) {
			debug("new page $page") unless exists $pagectime{$page};
			push @add, $file;
			$links{$page}=[];
			$pagesources{$page}=$file;
			$pagectime{$page}=mtime("$config{srcdir}/$file") 
				unless exists $pagectime{$page};
		}
	}
	my @del;
	foreach my $page (keys %oldpagemtime) {
		if (! $exists{$page}) {
			debug("removing old page $page");
			push @del, $pagesources{$page};
			prune($config{destdir}."/".$renderedfiles{$page});
			delete $renderedfiles{$page};
			$oldpagemtime{$page}=0;
			delete $pagesources{$page};
		}
	}
	
	# render any updated files
	foreach my $file (@files) {
		my $page=pagename($file);
		
		if (! exists $oldpagemtime{$page} ||
		    mtime("$config{srcdir}/$file") > $oldpagemtime{$page}) {
		    	debug("rendering changed file $file");
			render($file);
			$rendered{$file}=1;
		}
	}
	
	# if any files were added or removed, check to see if each page
	# needs an update due to linking to them or inlining them.
	# TODO: inefficient; pages may get rendered above and again here;
	# problem is the bestlink may have changed and we won't know until
	# now
	if (@add || @del) {
FILE:		foreach my $file (@files) {
			my $page=pagename($file);
			foreach my $f (@add, @del) {
				my $p=pagename($f);
				foreach my $link (@{$links{$page}}) {
					if (bestlink($page, $link) eq $p) {
		   				debug("rendering $file, which links to $p");
						render($file);
						$rendered{$file}=1;
						next FILE;
					}
				}
			}
		}
	}

	# Handle backlinks; if a page has added/removed links, update the
	# pages it links to. Also handle inlining here.
	# TODO: inefficient; pages may get rendered above and again here;
	# problem is the backlinks could be wrong in the first pass render
	# above
	if (%rendered || @del) {
		foreach my $f (@files) {
			my $p=pagename($f);
			if (exists $inlinepages{$p}) {
				foreach my $file (keys %rendered, @del) {
					my $page=pagename($file);
					if (globlist_match($page, $inlinepages{$p})) {
						debug("rendering $f, which inlines $page");
						render($f);
						last;
					}
				}
			}
		}
		
		my %linkchanged;
		foreach my $file (keys %rendered, @del) {
			my $page=pagename($file);
			
			if (exists $links{$page}) {
				foreach my $link (map { bestlink($page, $_) } @{$links{$page}}) {
					if (length $link &&
					    ! exists $oldlinks{$page} ||
					    ! grep { $_ eq $link } @{$oldlinks{$page}}) {
						$linkchanged{$link}=1;
					}
				}
			}
			if (exists $oldlinks{$page}) {
				foreach my $link (map { bestlink($page, $_) } @{$oldlinks{$page}}) {
					if (length $link &&
					    ! exists $links{$page} ||
					    ! grep { $_ eq $link } @{$links{$page}}) {
						$linkchanged{$link}=1;
					}
				}
			}
		}
		foreach my $link (keys %linkchanged) {
		    	my $linkfile=$pagesources{$link};
			if (defined $linkfile) {
				debug("rendering $linkfile, to update its backlinks");
				render($linkfile);
			}
		}
	}
} #}}}

1
