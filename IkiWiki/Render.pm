#!/usr/bin/perl

package IkiWiki;

use warnings;
use strict;
use File::Spec;

sub linkify ($$) { #{{{
	my $content=shift;
	my $page=shift;

	$content =~ s{(\\?)$config{wiki_link_regexp}}{
		$2 ? ( $1 ? "[[$2|$3]]" : htmllink($page, titlepage($3), 0, 0, pagetitle($2)))
		   : ( $1 ? "[[$3]]" :    htmllink($page, titlepage($3)))
	}eg;
	
	return $content;
} #}}}

my $_scrubber;
sub scrubber { #{{{
	return $_scrubber if defined $_scrubber;
	
	eval q{use HTML::Scrubber};
	# Lists based on http://feedparser.org/docs/html-sanitization.html
	$_scrubber = HTML::Scrubber->new(
		allow => [qw{
			a abbr acronym address area b big blockquote br
			button caption center cite code col colgroup dd del
			dfn dir div dl dt em fieldset font form h1 h2 h3 h4
			h5 h6 hr i img input ins kbd label legend li map
			menu ol optgroup option p pre q s samp select small
			span strike strong sub sup table tbody td textarea
			tfoot th thead tr tt u ul var
		}],
		default => [undef, { map { $_ => 1 } qw{
			abbr accept accept-charset accesskey action
			align alt axis border cellpadding cellspacing
			char charoff charset checked cite class
			clear cols colspan color compact coords
			datetime dir disabled enctype for frame
			headers height href hreflang hspace id ismap
			label lang longdesc maxlength media method
			multiple name nohref noshade nowrap prompt
			readonly rel rev rows rowspan rules scope
			selected shape size span src start summary
			tabindex target title type usemap valign
			value vspace width
		}}],
	);
	return $_scrubber;
} # }}}

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
		$content=Markdown::Markdown($content);
	}
	else {
		error("htmlization of $type not supported");
	}

	if ($config{sanitize}) {
		$content=scrubber()->scrub($content);
	}
	
	return $content;
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

sub preprocess ($$) { #{{{
	my $page=shift;
	my $content=shift;

	my %commands=(inline => \&preprocess_inline);
	
	my $handle=sub {
		my $escape=shift;
		my $command=shift;
		my $params=shift;
		if (length $escape) {
			return "[[$command $params]]";
		}
		elsif (exists $commands{$command}) {
			my %params;
			while ($params =~ /(\w+)=\"([^"]+)"(\s+|$)/g) {
				$params{$1}=$2;
			}
			return $commands{$command}->($page, %params);
		}
		else {
			return "[[bad directive $command]]";
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
		return htmlize($type, linkify(readfile(srcfile($file)), $parentpage));
	}
	else {
		return "";
	}
} #}}}

sub preprocess_inline ($@) { #{{{
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
	if (! exists $depends{$parentpage}) {
		$depends{$parentpage}=$params{pages};
	}
	else {
		$depends{$parentpage}.=" ".$params{pages};
	}

	my $ret="";
	
	if (exists $params{rootpage}) {
		# Add a blog post form, with a rss link button.
		my $formtemplate=HTML::Template->new(blind_cache => 1,
			filename => "$config{templatedir}/blogpost.tmpl");
		$formtemplate->param(cgiurl => $config{cgiurl});
		$formtemplate->param(rootpage => $params{rootpage});
		if ($config{rss}) {
			$formtemplate->param(rssurl => rsspage(basename($parentpage)));
		}
		$ret.=$formtemplate->output;
	}
	elsif ($config{rss}) {
		# Add a rss link button.
		my $linktemplate=HTML::Template->new(blind_cache => 1,
			filename => "$config{templatedir}/rsslink.tmpl");
		$linktemplate->param(rssurl => rsspage(basename($parentpage)));
		$ret.=$linktemplate->output;
	}
	
	my $template=HTML::Template->new(blind_cache => 1,
		filename => (($params{archive} eq "no") 
				? "$config{templatedir}/inlinepage.tmpl"
				: "$config{templatedir}/inlinepagetitle.tmpl"));
	
	my @pages;
	foreach my $page (blog_list($params{pages}, $params{show})) {
		next if $page eq $parentpage;
		push @pages, $page;
		$template->param(pagelink => htmllink($parentpage, $page));
		$template->param(content => get_inline_content($parentpage, $page))
			if $params{archive} eq "no";
		$template->param(ctime => scalar(gmtime($pagectime{$page})));
		$ret.=$template->output;
	}
	
	# TODO: should really add this to renderedfiles and call
	# check_overwrite, but currently renderedfiles
	# only supports listing one file per page.
	if ($config{rss}) {
		writefile(rsspage($parentpage), $config{destdir},
			genrss($parentpage, @pages));
	}
	
	return $ret;
} #}}}

sub genpage ($$$) { #{{{
	my $content=shift;
	my $page=shift;
	my $mtime=shift;

	my $title=pagetitle(basename($page));
	
	my $template=HTML::Template->new(blind_cache => 1,
		filename => "$config{templatedir}/page.tmpl");
	
	if (length $config{cgiurl}) {
		$template->param(editurl => cgiurl(do => "edit", page => $page));
		$template->param(prefsurl => cgiurl(do => "prefs"));
		if ($config{rcs}) {
			$template->param(recentchangesurl => cgiurl(do => "recentchanges"));
		}
	}

	if (length $config{historyurl}) {
		my $u=$config{historyurl};
		$u=~s/\[\[file\]\]/$pagesources{$page}/g;
		$template->param(historyurl => $u);
	}
	if ($config{hyperestraier}) {
		$template->param(hyperestraierurl => cgiurl());
	}

	$template->param(
		title => $title,
		wikiname => $config{wikiname},
		parentlinks => [parentlinks($page)],
		content => $content,
		backlinks => [backlinks($page)],
		discussionlink => htmllink($page, "Discussion", 1, 1),
		mtime => scalar(gmtime($mtime)),
		styleurl => styleurl($page),
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

sub genrss ($@) { #{{{
	my $page=shift;
	my @pages=@_;
	
	my $url="$config{url}/".htmlpage($page);
	
	my $template=HTML::Template->new(blind_cache => 1,
		filename => "$config{templatedir}/rsspage.tmpl");
	
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
		push @links, titlepage($2);
	}
	# Discussion links are a special case since they're not in the text
	# of the page, but on its template.
	return @links, "$page/discussion";
} #}}}

sub render ($) { #{{{
	my $file=shift;
	
	my $type=pagetype($file);
	my $srcfile=srcfile($file);
	if ($type ne 'unknown') {
		my $content=readfile($srcfile);
		my $page=pagename($file);
		
		$links{$page}=[findlinks($content, $page)];
		delete $depends{$page};
		
		$content=linkify($content, $page);
		$content=preprocess($page, $content);
		$content=htmlize($type, $content);
		
		check_overwrite("$config{destdir}/".htmlpage($page), $page);
		writefile(htmlpage($page), $config{destdir},
			genpage($content, $page, mtime($srcfile)));
		$oldpagemtime{$page}=time;
		$renderedfiles{$page}=htmlpage($page);
	}
	else {
		my $content=readfile($srcfile, 1);
		$links{$file}=[];
		check_overwrite("$config{destdir}/$file", $file);
		writefile($file, $config{destdir}, $content, 1);
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

sub estcfg () { #{{{
	my $estdir="$config{wikistatedir}/hyperestraier";
	my $cgi=basename($config{cgiurl});
	$cgi=~s/\..*$//;
	open(TEMPLATE, ">$estdir/$cgi.tmpl") ||
		error("write $estdir/$cgi.tmpl: $!");
	print TEMPLATE misctemplate("search", 
		"<!--ESTFORM-->\n\n<!--ESTRESULT-->\n\n<!--ESTINFO-->\n\n");
	close TEMPLATE;
	open(TEMPLATE, ">$estdir/$cgi.conf") ||
		error("write $estdir/$cgi.conf: $!");
	my $template=HTML::Template->new(
		filename => "$config{templatedir}/estseek.conf"
	);
	eval q{use Cwd 'abs_path'};
	$template->param(
		index => $estdir,
		tmplfile => "$estdir/$cgi.tmpl",
		destdir => abs_path($config{destdir}),
		url => $config{url},
	);
	print TEMPLATE $template->output;
	close TEMPLATE;
	$cgi="$estdir/".basename($config{cgiurl});
	unlink($cgi);
	symlink("/usr/lib/estraier/estseek.cgi", $cgi) ||
		error("symlink $cgi: $!");
} # }}}

sub estcmd ($;@) { #{{{
	my @params=split(' ', shift);
	push @params, "-cl", "$config{wikistatedir}/hyperestraier";
	if (@_) {
		push @params, "-";
	}
	
	my $pid=open(CHILD, "|-");
	if ($pid) {
		# parent
		foreach (@_) {
			print CHILD "$_\n";
		}
		close(CHILD) || error("estcmd @params exited nonzero: $?");
	}
	else {
		# child
		open(STDOUT, "/dev/null"); # shut it up (closing won't work)
		exec("estcmd", @params) || error("can't run estcmd");
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
				$File::Find::prune=1;
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
	find({
		no_chdir => 1,
		wanted => sub {
			if (/$config{wiki_file_prune_regexp}/) {
				$File::Find::prune=1;
			}
			elsif (! -d $_ && ! -l $_) {
				my ($f)=/$config{wiki_file_regexp}/; # untaint
				if (! defined $f) {
					warn("skipping bad filename $_\n");
				}
				else {
					# Don't add files that are in the
					# srcdir.
					$f=~s/^\Q$config{underlaydir}\E\/?//;
					if (! -e "$config{srcdir}/$f" && 
					    ! -l "$config{srcdir}/$f") {
						push @files, $f;
						$exists{pagename($f)}=1;
					}
				}
			}
		},
	}, $config{underlaydir});

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
			$pagectime{$page}=mtime(srcfile($file))
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
		    mtime(srcfile($file)) > $oldpagemtime{$page}) {
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
	# pages it links to. Also handles rebuilding dependat pages.
	# TODO: inefficient; pages may get rendered above and again here;
	# problem is the backlinks could be wrong in the first pass render
	# above
	if (%rendered || @del) {
		foreach my $f (@files) {
			my $p=pagename($f);
			if (exists $depends{$p}) {
				foreach my $file (keys %rendered, @del) {
					my $page=pagename($file);
					if (globlist_match($page, $depends{$p})) {
						debug("rendering $f, which depends on $page");
						render($f);
						$rendered{$f}=1;
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
				$rendered{$linkfile}=1;
			}
		}
	}

	if ($config{hyperestraier} && (%rendered || @del)) {
		debug("updating hyperestraier search index");
		if (%rendered) {
			estcmd("gather -cm -bc -cl -sd", 
				map { $config{destdir}."/".$renderedfiles{pagename($_)} }
				keys %rendered);
		}
		if (@del) {
			estcmd("purge -cl");
		}
		
		debug("generating hyperestraier cgi config");
		estcfg();
	}
} #}}}

1
