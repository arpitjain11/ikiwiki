#!/usr/bin/perl

package IkiWiki;

use warnings;
use strict;
use IkiWiki;
use Encode;

my %backlinks;
my $backlinks_calculated=0;

sub calculate_backlinks () {
	return if $backlinks_calculated;
	%backlinks=();
	foreach my $page (keys %links) {
		foreach my $link (@{$links{$page}}) {
			my $bestlink=bestlink($page, $link);
			if (length $bestlink && $bestlink ne $page) {
				$backlinks{$bestlink}{$page}=1;
			}
		}
	}
	$backlinks_calculated=1;
}

sub backlinks ($) {
	my $page=shift;

	calculate_backlinks();

	my @links;
	foreach my $p (keys %{$backlinks{$page}}) {
		my $href=urlto($p, $page);
                
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
	return @links;
}

sub genpage ($$) {
	my $page=shift;
	my $content=shift;

	my $templatefile;
	run_hooks(templatefile => sub {
		return if defined $templatefile;
		my $file=shift->(page => $page);
		if (defined $file && defined template_file($file)) {
			$templatefile=$file;
		}
	});
	my $template=template(defined $templatefile ? $templatefile : 'page.tmpl', blind_cache => 1);
	my $actions=0;

	if (length $config{cgiurl}) {
		$template->param(editurl => cgiurl(do => "edit", page => $page))
			if IkiWiki->can("cgi_editpage");
		$template->param(prefsurl => cgiurl(do => "prefs"));
		$actions++;
	}
		
	if (defined $config{historyurl} && length $config{historyurl}) {
		my $u=$config{historyurl};
		$u=~s/\[\[file\]\]/$pagesources{$page}/g;
		$template->param(historyurl => $u);
		$actions++;
	}
	if ($config{discussion}) {
		my $discussionlink=gettext("discussion");
		if ($page !~ /.*\/\Q$discussionlink\E$/ &&
		   (length $config{cgiurl} ||
		    exists $links{$page."/".$discussionlink})) {
			$template->param(discussionlink => htmllink($page, $page, gettext("Discussion"), noimageinline => 1, forcesubpage => 1));
			$actions++;
		}
	}

	if ($actions) {
		$template->param(have_actions => 1);
	}

	my @backlinks=sort { $a->{page} cmp $b->{page} } backlinks($page);
	my ($backlinks, $more_backlinks);
	if (@backlinks <= $config{numbacklinks} || ! $config{numbacklinks}) {
		$backlinks=\@backlinks;
		$more_backlinks=[];
	}
	else {
		$backlinks=[@backlinks[0..$config{numbacklinks}-1]];
		$more_backlinks=[@backlinks[$config{numbacklinks}..$#backlinks]];
	}

	$template->param(
		title => $page eq 'index' 
			? $config{wikiname} 
			: pagetitle(basename($page)),
		wikiname => $config{wikiname},
		content => $content,
		backlinks => $backlinks,
		more_backlinks => $more_backlinks,
		mtime => displaytime($pagemtime{$page}),
		ctime => displaytime($pagectime{$page}),
		baseurl => baseurl($page),
	);

	run_hooks(pagetemplate => sub {
		shift->(page => $page, destpage => $page, template => $template);
	});
	
	$content=$template->output;
	
	run_hooks(postscan => sub {
		shift->(page => $page, content => $content);
	});

	run_hooks(format => sub {
		$content=shift->(
			page => $page,
			content => $content,
		);
	});

	return $content;
}

sub scan ($) {
	my $file=shift;

	my $type=pagetype($file);
	if (defined $type) {
		my $srcfile=srcfile($file);
		my $content=readfile($srcfile);
		my $page=pagename($file);
		will_render($page, htmlpage($page), 1);

		if ($config{discussion}) {
			# Discussion links are a special case since they're
			# not in the text of the page, but on its template.
			$links{$page}=[ $page."/".gettext("discussion") ];
		}
		else {
			$links{$page}=[];
		}

		run_hooks(scan => sub {
			shift->(
				page => $page,
				content => $content,
			);
		});

		# Preprocess in scan-only mode.
		preprocess($page, $page, $content, 1);
	}
	else {
		will_render($file, $file, 1);
	}
}

sub fast_file_copy (@) {
	my $srcfile=shift;
	my $destfile=shift;
	my $srcfd=shift;
	my $destfd=shift;
	my $cleanup=shift;

	my $blksize = 16384;
	my ($len, $buf, $written);
	while ($len = sysread $srcfd, $buf, $blksize) {
		if (! defined $len) {
			next if $! =~ /^Interrupted/;
			error("failed to read $srcfile: $!", $cleanup);
		}
		my $offset = 0;
		while ($len) {
			defined($written = syswrite $destfd, $buf, $len, $offset)
				or error("failed to write $destfile: $!", $cleanup);
			$len -= $written;
			$offset += $written;
		}
	}
}

sub render ($) {
	my $file=shift;
	
	my $type=pagetype($file);
	my $srcfile=srcfile($file);
	if (defined $type) {
		my $page=pagename($file);
		delete $depends{$page};
		will_render($page, htmlpage($page), 1);
		return if $type=~/^_/;
		
		my $content=htmlize($page, $page, $type,
			linkify($page, $page,
			preprocess($page, $page,
			filter($page, $page,
			readfile($srcfile)))));
		
		my $output=htmlpage($page);
		writefile($output, $config{destdir}, genpage($page, $content));
	}
	else {
		delete $depends{$file};
		will_render($file, $file, 1);
		
		if ($config{hardlink}) {
			# only hardlink if owned by same user
			my @stat=stat($srcfile);
			if ($stat[4] == $>) {
				prep_writefile($file, $config{destdir});
				unlink($config{destdir}."/".$file);
				if (link($srcfile, $config{destdir}."/".$file)) {
					return;
				}
			}
			# if hardlink fails, fall back to copying
		}
		
		my $srcfd=readfile($srcfile, 1, 1);
		writefile($file, $config{destdir}, undef, 1, sub {
			fast_file_copy($srcfile, $file, $srcfd, @_);
		});
	}
}

sub prune ($) {
	my $file=shift;

	unlink($file);
	my $dir=dirname($file);
	while (rmdir($dir)) {
		$dir=dirname($dir);
	}
}

sub refresh () {
	# security check, avoid following symlinks in the srcdir path by default
	my $test=$config{srcdir};
	while (length $test) {
		if (-l $test && ! $config{allow_symlinks_before_srcdir}) {
			error(sprintf(gettext("symlink found in srcdir path (%s) -- set allow_symlinks_before_srcdir to allow this"), $test));
		}
		unless ($test=~s/\/+$//) {
			$test=dirname($test);
		}
	}
	
	run_hooks(refresh => sub { shift->() });

	# find existing pages
	my %exists;
	my @files;
	eval q{use File::Find};
	error($@) if $@;
	find({
		no_chdir => 1,
		wanted => sub {
			$_=decode_utf8($_);
			if (file_pruned($_, $config{srcdir})) {
				$File::Find::prune=1;
			}
			elsif (! -l $_ && ! -d _) {
				my ($f)=/$config{wiki_file_regexp}/; # untaint
				if (! defined $f) {
					warn(sprintf(gettext("skipping bad filename %s"), $_)."\n");
				}
				else {
					$f=~s/^\Q$config{srcdir}\E\/?//;
					push @files, $f;
					my $pagename = pagename($f);
					if ($exists{$pagename}) {
						debug(sprintf(gettext("%s has multiple possible source pages"), $pagename));
					}
					$exists{$pagename}=1;
				}
			}
		},
	}, $config{srcdir});
	foreach my $dir (@{$config{underlaydirs}}, $config{underlaydir}) {
		find({
			no_chdir => 1,
			wanted => sub {
				$_=decode_utf8($_);
				if (file_pruned($_, $dir)) {
					$File::Find::prune=1;
				}
				elsif (! -l $_ && ! -d _) {
					my ($f)=/$config{wiki_file_regexp}/; # untaint
					if (! defined $f) {
						warn(sprintf(gettext("skipping bad filename %s"), $_)."\n");
					}
					else {
						$f=~s/^\Q$dir\E\/?//;
						# avoid underlaydir
						# override attacks; see
						# security.mdwn
						if (! -l "$config{srcdir}/$f" && 
						    ! -e _) {
						    	my $page=pagename($f);
							if (! $exists{$page}) {
								push @files, $f;
								$exists{$page}=1;
							}
						}
					}
				}
			},
		}, $dir);
	};

	my (%rendered, @add, @del, @internal);
	# check for added or removed pages
	foreach my $file (@files) {
		my $page=pagename($file);
		if (exists $pagesources{$page} && $pagesources{$page} ne $file) {
			# the page has changed its type
			$forcerebuild{$page}=1;
		}
		$pagesources{$page}=$file;
		if (! $pagemtime{$page}) {
			if (isinternal($page)) {
				push @internal, $file;
			}
			else {
				push @add, $file;
				if ($config{getctime} && -e "$config{srcdir}/$file") {
					eval {
						my $time=rcs_getctime("$config{srcdir}/$file");
						$pagectime{$page}=$time;
					};
					if ($@) {
						print STDERR $@;
					}
				}
			}
			$pagecase{lc $page}=$page;
			if (! exists $pagectime{$page}) {
				$pagectime{$page}=(srcfile_stat($file))[10];
			}
		}
	}
	foreach my $page (keys %pagemtime) {
		if (! $exists{$page}) {
			if (isinternal($page)) {
				push @internal, $pagesources{$page};
			}
			else {
				debug(sprintf(gettext("removing old page %s"), $page));
				push @del, $pagesources{$page};
			}
			$links{$page}=[];
			$renderedfiles{$page}=[];
			$pagemtime{$page}=0;
			prune($config{destdir}."/".$_)
				foreach @{$oldrenderedfiles{$page}};
			delete $pagesources{$page};
			foreach (keys %destsources) {
				if ($destsources{$_} eq $page) {
					delete $destsources{$_};
				}
			}
		}
	}

	# find changed and new files
	my @needsbuild;
	foreach my $file (@files) {
		my $page=pagename($file);
		my ($srcfile, @stat)=srcfile_stat($file);
		if (! exists $pagemtime{$page} ||
		    $stat[9] > $pagemtime{$page} ||
	    	    $forcerebuild{$page}) {
			$pagemtime{$page}=$stat[9];
			if (isinternal($page)) {
				push @internal, $file;
				# Preprocess internal page in scan-only mode.
				preprocess($page, $page, readfile($srcfile), 1);
			}
			else {
				push @needsbuild, $file;
			}
		}
	}
	run_hooks(needsbuild => sub { shift->(\@needsbuild) });

	# scan and render files
	foreach my $file (@needsbuild) {
		debug(sprintf(gettext("scanning %s"), $file));
		scan($file);
	}
	calculate_backlinks();
	foreach my $file (@needsbuild) {
		debug(sprintf(gettext("rendering %s"), $file));
		render($file);
		$rendered{$file}=1;
	}
	foreach my $file (@internal) {
		# internal pages are not rendered
		my $page=pagename($file);
		delete $depends{$page};
		foreach my $old (@{$renderedfiles{$page}}) {
			delete $destsources{$old};
		}
		$renderedfiles{$page}=[];
	}
	
	# rebuild pages that link to added or removed pages
	if (@add || @del) {
		foreach my $f (@add, @del) {
			my $p=pagename($f);
			foreach my $page (keys %{$backlinks{$p}}) {
				my $file=$pagesources{$page};
				next if $rendered{$file};
		   		debug(sprintf(gettext("rendering %s, which links to %s"), $file, $p));
				render($file);
				$rendered{$file}=1;
			}
		}
	}

	if (%rendered || @del || @internal) {
		my @changed=(keys %rendered, @del);

		# rebuild dependant pages
		foreach my $f (@files) {
			next if $rendered{$f};
			my $p=pagename($f);
			if (exists $depends{$p}) {
				# only consider internal files
				# if the page explicitly depends on such files
				foreach my $file (@changed, $depends{$p}=~/internal\(/ ? @internal : ()) {
					next if $f eq $file;
					my $page=pagename($file);
					if (pagespec_match($page, $depends{$p}, location => $p)) {
						debug(sprintf(gettext("rendering %s, which depends on %s"), $f, $page));
						render($f);
						$rendered{$f}=1;
						last;
					}
				}
			}
		}
		
		# handle backlinks; if a page has added/removed links,
		# update the pages it links to
		my %linkchanged;
		foreach my $file (@changed) {
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
				next if $rendered{$linkfile};
				debug(sprintf(gettext("rendering %s, to update its backlinks"), $linkfile));
				render($linkfile);
				$rendered{$linkfile}=1;
			}
		}
	}

	# remove no longer rendered files
	foreach my $src (keys %rendered) {
		my $page=pagename($src);
		foreach my $file (@{$oldrenderedfiles{$page}}) {
			if (! grep { $_ eq $file } @{$renderedfiles{$page}}) {
				debug(sprintf(gettext("removing %s, no longer rendered by %s"), $file, $page));
				prune($config{destdir}."/".$file);
			}
		}
	}

	if (@del) {
		run_hooks(delete => sub { shift->(@del) });
	}
	if (%rendered) {
		run_hooks(change => sub { shift->(keys %rendered) });
	}
}

sub commandline_render () {
	lockwiki();
	loadindex();
	unlockwiki();

	my $srcfile=possibly_foolish_untaint($config{render});
	my $file=$srcfile;
	$file=~s/\Q$config{srcdir}\E\/?//;

	my $type=pagetype($file);
	die sprintf(gettext("ikiwiki: cannot render %s"), $srcfile)."\n" unless defined $type;
	my $content=readfile($srcfile);
	my $page=pagename($file);
	$pagesources{$page}=$file;
	$content=filter($page, $page, $content);
	$content=preprocess($page, $page, $content);
	$content=linkify($page, $page, $content);
	$content=htmlize($page, $page, $type, $content);
	$pagemtime{$page}=(stat($srcfile))[9];
	$pagectime{$page}=$pagemtime{$page} if ! exists $pagectime{$page};

	print genpage($page, $content);
	exit 0;
}

1
