#!/usr/bin/perl

package IkiWiki;

use warnings;
use strict;
use IkiWiki;
use Encode;

sub linkify ($$$) { #{{{
	my $lpage=shift; # the page containing the links
	my $page=shift; # the page the link will end up on (different for inline)
	my $content=shift;

	$content =~ s{(\\?)$config{wiki_link_regexp}}{
		$2 ? ( $1 ? "[[$2|$3]]" : htmllink($lpage, $page, titlepage($3), 0, 0, pagetitle($2)))
		   : ( $1 ? "[[$3]]" :    htmllink($lpage, $page, titlepage($3)))
	}eg;
	
	return $content;
} #}}}

sub htmlize ($$) { #{{{
	my $type=shift;
	my $content=shift;
	
	if (exists $hooks{htmlize}{$type}) {
		$content=$hooks{htmlize}{$type}{call}->($content);
	}
	else {
		error("htmlization of $type not supported");
	}

	run_hooks(sanitize => sub {
		$content=shift->($content);
	});
	
	return $content;
} #}}}

sub backlinks ($) { #{{{
	my $page=shift;

	my @links;
	foreach my $p (keys %links) {
		next if bestlink($page, $p) eq $page;
		if (grep { length $_ && bestlink($p, $_) eq $page } @{$links{$p}}) {
			my $href=abs2rel(htmlpage($p), dirname($page));
			
			# Trim common dir prefixes from both pages.
			my $p_trimmed=$p;
			my $page_trimmed=$page;
			my $dir;
			1 while (($dir)=$page_trimmed=~m!^([^/]+/)!) &&
			        defined $dir &&
			        $p_trimmed=~s/^\Q$dir\E// &&
			        $page_trimmed=~s/^\Q$dir\E//;
				       
			push @links, { url => $href, page => pagetitle($p_trimmed) };
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
	return if $page eq 'index'; # toplevel
	foreach my $dir (reverse split("/", $page)) {
		if (! $skip) {
			$path.="../";
			unshift @ret, { url => $path.htmlpage($dir), page => pagetitle($dir) };
		}
		else {
			$skip=0;
		}
	}
	unshift @ret, { url => length $path ? $path : ".", page => $config{wikiname} };
	return @ret;
} #}}}

my %preprocessing;
sub preprocess ($$$) { #{{{
	my $page=shift; # the page the data comes from
	my $destpage=shift; # the page the data will appear in (different for inline)
	my $content=shift;

	my $handle=sub {
		my $escape=shift;
		my $command=shift;
		my $params=shift;
		if (length $escape) {
			return "[[$command $params]]";
		}
		elsif (exists $hooks{preprocess}{$command}) {
			# Note: preserve order of params, some plugins may
			# consider it significant.
			my @params;
			while ($params =~ /(?:(\w+)=)?(?:"""(.*?)"""|"([^"]+)"|(\S+))(?:\s+|$)/sg) {
				my $key=$1;
				my $val;
				if (defined $2) {
					$val=$2;
					$val=~s/\r\n/\n/mg;
					$val=~s/^\n+//g;
					$val=~s/\n+$//g;
				}
				elsif (defined $3) {
					$val=$3;
				}
				elsif (defined $4) {
					$val=$4;
				}

				if (defined $key) {
					push @params, $key, $val;
				}
				else {
					push @params, $val, '';
				}
			}
			if ($preprocessing{$page}++ > 10) {
				# Avoid loops of preprocessed pages preprocessing
				# other pages that preprocess them, etc.
				return "[[$command preprocessing loop detected on $page at depth $preprocessing{$page}]]";
			}
			my $ret=$hooks{preprocess}{$command}{call}->(
				@params,
				page => $page,
				destpage => $destpage,
			);
			$preprocessing{$page}--;
			return $ret;
		}
		else {
			return "[[$command $params]]";
		}
	};
	
	$content =~ s{(\\?)\[\[(\w+)\s+((?:(?:\w+=)?(?:""".*?"""|"[^"]+"|[^\s\]]+)\s*)*)\]\]}{$handle->($1, $2, $3)}seg;
	return $content;
} #}}}

sub add_depends ($$) { #{{{
	my $page=shift;
	my $pagespec=shift;
	
	if (! exists $depends{$page}) {
		$depends{$page}=$pagespec;
	}
	else {
		$depends{$page}=pagespec_merge($depends{$page}, $pagespec);
	}
} # }}}

sub genpage ($$$) { #{{{
	my $page=shift;
	my $content=shift;
	my $mtime=shift;

	my $template=template("page.tmpl", blind_cache => 1);
	my $actions=0;

	if (length $config{cgiurl}) {
		$template->param(editurl => cgiurl(do => "edit", page => $page));
		$template->param(prefsurl => cgiurl(do => "prefs"));
		if ($config{rcs}) {
			$template->param(recentchangesurl => cgiurl(do => "recentchanges"));
		}
		$actions++;
	}

	if (length $config{historyurl}) {
		my $u=$config{historyurl};
		$u=~s/\[\[file\]\]/$pagesources{$page}/g;
		$template->param(historyurl => $u);
		$actions++;
	}
	if ($config{discussion}) {
		$template->param(discussionlink => htmllink($page, $page, "Discussion", 1, 1));
		$actions++;
	}

	if ($actions) {
		$template->param(have_actions => 1);
	}

	$template->param(
		title => $page eq 'index' 
			? $config{wikiname} 
			: pagetitle(basename($page)),
		wikiname => $config{wikiname},
		parentlinks => [parentlinks($page)],
		content => $content,
		backlinks => [backlinks($page)],
		mtime => displaytime($mtime),
		baseurl => baseurl($page),
	);

	run_hooks(pagetemplate => sub {
		shift->(page => $page, destpage => $page, template => $template);
	});
	
	$content=$template->output;

	run_hooks(format => sub {
		$content=shift->($content);
	});

	return $content;
} #}}}

sub check_overwrite ($$) { #{{{
	# Important security check. Make sure to call this before saving
	# any files to the source directory.
	my $dest=shift;
	my $src=shift;
	
	if (! exists $renderedfiles{$src} && -e $dest && ! $config{rebuild}) {
		error("$dest already exists and was not rendered from $src before");
	}
} #}}}

sub displaytime ($) { #{{{
	my $time=shift;

	eval q{use POSIX};
	# strftime doesn't know about encodings, so make sure
	# its output is properly treated as utf8
	return decode_utf8(POSIX::strftime(
			$config{timeformat}, localtime($time)));
} #}}}

sub mtime ($) { #{{{
	my $file=shift;
	
	return (stat($file))[9];
} #}}}

sub findlinks ($$) { #{{{
	my $page=shift;
	my $content=shift;

	my @links;
	while ($content =~ /(?<!\\)$config{wiki_link_regexp}/g) {
		push @links, titlepage($2);
	}
	if ($config{discussion}) {
		# Discussion links are a special case since they're not in the
		# text of the page, but on its template.
		return @links, "$page/discussion";
	}
	else {
		return @links;
	}
} #}}}

sub filter ($$) {
	my $page=shift;
	my $content=shift;

	run_hooks(filter => sub {
		$content=shift->(page => $page, content => $content);
	});

	return $content;
}

sub render ($) { #{{{
	my $file=shift;
	
	my $type=pagetype($file);
	my $srcfile=srcfile($file);
	if (defined $type) {
		my $content=readfile($srcfile);
		my $page=pagename($file);
		delete $depends{$page};
		
		$content=filter($page, $content);
		
		$links{$page}=[findlinks($page, $content)];
		
		$content=preprocess($page, $page, $content);
		$content=linkify($page, $page, $content);
		$content=htmlize($type, $content);
		
		check_overwrite("$config{destdir}/".htmlpage($page), $page);
		writefile(htmlpage($page), $config{destdir},
			genpage($page, $content, mtime($srcfile)));
		$oldpagemtime{$page}=time;
		$renderedfiles{$page}=htmlpage($page);
	}
	else {
		my $content=readfile($srcfile, 1);
		$links{$file}=[];
		delete $depends{$file};
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

sub refresh () { #{{{
	# find existing pages
	my %exists;
	my @files;
	eval q{use File::Find};
	find({
		no_chdir => 1,
		wanted => sub {
			$_=decode_utf8($_);
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
			$_=decode_utf8($_);
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
			$pagecase{lc $page}=$page;
			$pagesources{$page}=$file;
			if ($config{getctime} && -e "$config{srcdir}/$file") {
				$pagectime{$page}=rcs_getctime("$config{srcdir}/$file");
			}
			elsif (! exists $pagectime{$page}) {
				$pagectime{$page}=mtime(srcfile($file));
			}
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
		    mtime(srcfile($file)) > $oldpagemtime{$page} ||
	    	    $forcerebuild{$page}) {
		    	debug("rendering $file");
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
	# pages it links to. Also handles rebuilding dependant pages.
	# TODO: inefficient; pages may get rendered above and again here;
	# problem is the backlinks could be wrong in the first pass render
	# above
	if (%rendered || @del) {
		foreach my $f (@files) {
			my $p=pagename($f);
			if (exists $depends{$p}) {
				foreach my $file (keys %rendered, @del) {
					next if $f eq $file;
					my $page=pagename($file);
					if (pagespec_match($page, $depends{$p})) {
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
					    (! exists $oldlinks{$page} ||
					     ! grep { bestlink($page, $_) eq $link } @{$oldlinks{$page}})) {
						$linkchanged{$link}=1;
					}
				}
			}
			if (exists $oldlinks{$page}) {
				foreach my $link (map { bestlink($page, $_) } @{$oldlinks{$page}}) {
					if (length $link &&
					    (! exists $links{$page} || 
					     ! grep { bestlink($page, $_) eq $link } @{$links{$page}})) {
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

	if (@del) {
		run_hooks(delete => sub { shift->(@del) });
	}
	if (%rendered) {
		run_hooks(change => sub { shift->(keys %rendered) });
	}
} #}}}

1
