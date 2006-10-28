#!/usr/bin/perl

package IkiWiki;

use warnings;
use strict;
use IkiWiki;
use Encode;

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
		$content=shift->(
			page => $page,
			content => $content,
		);
	});

	return $content;
} #}}}

sub mtime ($) { #{{{
	my $file=shift;
	
	return (stat($file))[9];
} #}}}

sub scan ($) { #{{{
	my $file=shift;

	my $type=pagetype($file);
	if (defined $type) {
		my $srcfile=srcfile($file);
		my $content=readfile($srcfile);
		my $page=pagename($file);

		my @links;
		while ($content =~ /(?<!\\)$config{wiki_link_regexp}/g) {
			push @links, titlepage($2);
		}
		if ($config{discussion}) {
			# Discussion links are a special case since they're not in the
			# text of the page, but on its template.
			push @links, "$page/discussion";
		}
		$links{$page}=\@links;
	}
} #}}}

sub render ($) { #{{{
	my $file=shift;
	
	my $type=pagetype($file);
	my $srcfile=srcfile($file);
	if (defined $type) {
		my $content=readfile($srcfile);
		my $page=pagename($file);
		delete $depends{$page};
		will_render($page, htmlpage($page), 1);
		
		$content=filter($page, $content);
		$content=preprocess($page, $page, $content);
		$content=linkify($page, $page, $content);
		$content=htmlize($page, $type, $content);
		
		writefile(htmlpage($page), $config{destdir},
			genpage($page, $content, mtime($srcfile)));
		$oldpagemtime{$page}=time;
	}
	else {
		my $content=readfile($srcfile, 1);
		delete $depends{$file};
		will_render($file, $file, 1);
		writefile($file, $config{destdir}, $content, 1);
		$oldpagemtime{$file}=time;
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
			push @add, $file;
			scan($file);
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
			$links{$page}=[];
			$renderedfiles{$page}=[];
			$oldpagemtime{$page}=0;
			prune($config{destdir}."/".$_)
				foreach @{$oldrenderedfiles{$page}};
			delete $pagesources{$page};
		}
	}
	
	# scan updated files to update info about them
	foreach my $file (@files) {
		my $page=pagename($file);
		
		if (! exists $oldpagemtime{$page} ||
		    mtime(srcfile($file)) > $oldpagemtime{$page} ||
	    	    $forcerebuild{$page}) {
		    	debug("scanning $file");
			scan($file);
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
	# needs an update due to linking to them or inlining them
	if (@add || @del) {
FILE:		foreach my $file (@files) {
			next if $rendered{$file};
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
	if (%rendered || @del) {
		foreach my $f (@files) {
			next if $rendered{$f};
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
				next if $rendered{$linkfile};
				debug("rendering $linkfile, to update its backlinks");
				render($linkfile);
				$rendered{$linkfile}=1;
			}
		}
	}

	# Remove no longer rendered files.
	foreach my $src (keys %rendered) {
		my $page=pagename($src);
		foreach my $file (@{$oldrenderedfiles{$page}}) {
			if (! grep { $_ eq $file } @{$renderedfiles{$page}}) {
				debug("removing $file, no longer rendered by $page");
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
} #}}}

sub commandline_render () { #{{{
	loadplugins();
	checkconfig();
	lockwiki();
	loadindex();
	unlockwiki();

	my $srcfile=possibly_foolish_untaint($config{render});
	my $file=$srcfile;
	$file=~s/\Q$config{srcdir}\E\/?//;

	my $type=pagetype($file);
	die "ikiwiki: cannot render $srcfile\n" unless defined $type;
	my $content=readfile($srcfile);
	my $page=pagename($file);
	$pagesources{$page}=$file;
	$content=filter($page, $content);
	$content=preprocess($page, $page, $content);
	$content=linkify($page, $page, $content);
	$content=htmlize($page, $type, $content);

	print genpage($page, $content, mtime($srcfile));
	exit 0;
} #}}}

1
