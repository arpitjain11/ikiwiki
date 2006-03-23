package IkiWiki;

use warnings;
use strict;
use File::Spec;

sub linkify ($$) { #{{{
	my $content=shift;
	my $page=shift;

	$content =~ s{(\\?)$config{wiki_link_regexp}}{
		$1 ? "[[$2]]" : htmllink($page, $2)
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

sub finalize ($$$) { #{{{
	my $content=shift;
	my $page=shift;
	my $mtime=shift;

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
	my $page=shift;
	
	return (stat($page))[9];
} #}}}

sub findlinks ($$) { #{{{
	my $content=shift;
	my $page=shift;

	my @links;
	while ($content =~ /(?<!\\)$config{wiki_link_regexp}/g) {
		push @links, lc($1);
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
		
		$content=linkify($content, $page);
		$content=htmlize($type, $content);
		$content=finalize($content, $page,
			mtime("$config{srcdir}/$file"));
		
		check_overwrite("$config{destdir}/".htmlpage($page), $page);
		writefile("$config{destdir}/".htmlpage($page), $content);
		$oldpagemtime{$page}=time;
		$renderedfiles{$page}=htmlpage($page);
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
			debug("new page $page");
			push @add, $file;
			$links{$page}=[];
			$pagesources{$page}=$file;
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
	# needs an update due to linking to them
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

	# handle backlinks; if a page has added/removed links, update the
	# pages it links to
	# TODO: inefficient; pages may get rendered above and again here;
	# problem is the backlinks could be wrong in the first pass render
	# above
	if (%rendered) {
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
