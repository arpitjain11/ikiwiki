#!/usr/bin/perl

package IkiWiki;
use warnings;
use strict;
use File::Spec;
use HTML::Template;

use vars qw{%config %links %oldlinks %oldpagemtime %pagectime
            %renderedfiles %pagesources %depends %hooks};

sub defaultconfig () { #{{{
	wiki_file_prune_regexp => qr{((^|/).svn/|\.\.|^\.|\/\.|\.html?$|\.rss$)},
	wiki_link_regexp => qr/\[\[(?:([^\]\|]+)\|)?([^\s\]]+)\]\]/,
	wiki_processor_regexp => qr/\[\[(\w+)\s+([^\]]*)\]\]/,
	wiki_file_regexp => qr/(^[-[:alnum:]_.:\/+]+$)/,
	verbose => 0,
	wikiname => "wiki",
	default_pageext => ".mdwn",
	cgi => 0,
	rcs => 'svn',
	notify => 0,
	url => '',
	cgiurl => '',
	historyurl => '',
	diffurl => '',
	anonok => 0,
	rss => 0,
	discussion => 1,
	rebuild => 0,
	refresh => 0,
	getctime => 0,
	wrapper => undef,
	wrappermode => undef,
	svnrepo => undef,
	svnpath => "trunk",
	srcdir => undef,
	destdir => undef,
	templatedir => "/usr/share/ikiwiki/templates",
	underlaydir => "/usr/share/ikiwiki/basewiki",
	setup => undef,
	adminuser => undef,
	adminemail => undef,
	plugin => [qw{inline htmlscrubber}],
} #}}}
	    
sub checkconfig () { #{{{
	if ($config{cgi} && ! length $config{url}) {
		error("Must specify url to wiki with --url when using --cgi\n");
	}
	if ($config{rss} && ! length $config{url}) {
		error("Must specify url to wiki with --url when using --rss\n");
	}
	
	$config{wikistatedir}="$config{srcdir}/.ikiwiki"
		unless exists $config{wikistatedir};
	
	if ($config{rcs}) {
		eval qq{require IkiWiki::Rcs::$config{rcs}};
		if ($@) {
			error("Failed to load RCS module IkiWiki::Rcs::$config{rcs}: $@");
		}
	}
	else {
		require IkiWiki::Rcs::Stub;
	}

	foreach my $plugin (@{$config{plugin}}) {
		my $mod="IkiWiki::Plugin::".possibly_foolish_untaint($plugin);
		eval qq{use $mod};
		if ($@) {
			error("Failed to load plugin $mod: $@");
		}
	}

	if (exists $hooks{checkconfig}) {
                foreach my $id (keys %{$hooks{checkconfig}}) {
                        $hooks{checkconfig}{$id}{call}->();
                }
        }
} #}}}

sub error ($) { #{{{
	if ($config{cgi}) {
		print "Content-type: text/html\n\n";
		print misctemplate("Error", "<p>Error: @_</p>");
	}
	die @_;
} #}}}

sub debug ($) { #{{{
	return unless $config{verbose};
	if (! $config{cgi}) {
		print "@_\n";
	}
	else {
		print STDERR "@_\n";
	}
} #}}}

sub possibly_foolish_untaint ($) { #{{{
	my $tainted=shift;
	my ($untainted)=$tainted=~/(.*)/;
	return $untainted;
} #}}}

sub basename ($) { #{{{
	my $file=shift;

	$file=~s!.*/+!!;
	return $file;
} #}}}

sub dirname ($) { #{{{
	my $file=shift;

	$file=~s!/*[^/]+$!!;
	return $file;
} #}}}

sub pagetype ($) { #{{{
	my $page=shift;
	
	if ($page =~ /\.mdwn$/) {
		return ".mdwn";
	}
	else {
		return "unknown";
	}
} #}}}

sub pagename ($) { #{{{
	my $file=shift;

	my $type=pagetype($file);
	my $page=$file;
	$page=~s/\Q$type\E*$// unless $type eq 'unknown';
	return $page;
} #}}}

sub htmlpage ($) { #{{{
	my $page=shift;

	return $page.".html";
} #}}}

sub srcfile ($) { #{{{
	my $file=shift;

	return "$config{srcdir}/$file" if -e "$config{srcdir}/$file";
	return "$config{underlaydir}/$file" if -e "$config{underlaydir}/$file";
	error("internal error: $file cannot be found");
} #}}}

sub readfile ($;$) { #{{{
	my $file=shift;
	my $binary=shift;

	if (-l $file) {
		error("cannot read a symlink ($file)");
	}
	
	local $/=undef;
	open (IN, $file) || error("failed to read $file: $!");
	binmode(IN) if $binary;
	my $ret=<IN>;
	close IN;
	return $ret;
} #}}}

sub writefile ($$$;$) { #{{{
	my $file=shift; # can include subdirs
	my $destdir=shift; # directory to put file in
	my $content=shift;
	my $binary=shift;
	
	my $test=$file;
	while (length $test) {
		if (-l "$destdir/$test") {
			error("cannot write to a symlink ($test)");
		}
		$test=dirname($test);
	}

	my $dir=dirname("$destdir/$file");
	if (! -d $dir) {
		my $d="";
		foreach my $s (split(m!/+!, $dir)) {
			$d.="$s/";
			if (! -d $d) {
				mkdir($d) || error("failed to create directory $d: $!");
			}
		}
	}
	
	open (OUT, ">$destdir/$file") || error("failed to write $destdir/$file: $!");
	binmode(OUT) if $binary;
	print OUT $content;
	close OUT;
} #}}}

sub bestlink ($$) { #{{{
	# Given a page and the text of a link on the page, determine which
	# existing page that link best points to. Prefers pages under a
	# subdirectory with the same name as the source page, failing that
	# goes down the directory tree to the base looking for matching
	# pages.
	my $page=shift;
	my $link=lc(shift);
	
	my $cwd=$page;
	do {
		my $l=$cwd;
		$l.="/" if length $l;
		$l.=$link;

		if (exists $links{$l}) {
			#debug("for $page, \"$link\", use $l");
			return $l;
		}
	} while $cwd=~s!/?[^/]+$!!;

	#print STDERR "warning: page $page, broken link: $link\n";
	return "";
} #}}}

sub isinlinableimage ($) { #{{{
	my $file=shift;
	
	$file=~/\.(png|gif|jpg|jpeg)$/i;
} #}}}

sub pagetitle ($) { #{{{
	my $page=shift;
	$page=~s/__(\d+)__/&#$1;/g;
	$page=~y/_/ /;
	return $page;
} #}}}

sub titlepage ($) { #{{{
	my $title=shift;
	$title=~y/ /_/;
	$title=~s/([^-[:alnum:]_:+\/.])/"__".ord($1)."__"/eg;
	return $title;
} #}}}

sub cgiurl (@) { #{{{
	my %params=@_;

	return $config{cgiurl}."?".join("&amp;", map "$_=$params{$_}", keys %params);
} #}}}

sub styleurl (;$) { #{{{
	my $page=shift;

	return "$config{url}/style.css" if ! defined $page;
	
	$page=~s/[^\/]+$//;
	$page=~s/[^\/]+\//..\//g;
	return $page."style.css";
} #}}}

sub htmllink ($$$;$$$) { #{{{
	my $lpage=shift; # the page doing the linking
	my $page=shift; # the page that will contain the link (different for inline)
	my $link=shift;
	my $noimageinline=shift; # don't turn links into inline html images
	my $forcesubpage=shift; # force a link to a subpage
	my $linktext=shift; # set to force the link text to something

	my $bestlink;
	if (! $forcesubpage) {
		$bestlink=bestlink($lpage, $link);
	}
	else {
		$bestlink="$lpage/".lc($link);
	}

	$linktext=pagetitle(basename($link)) unless defined $linktext;
	
	return $linktext if length $bestlink && $page eq $bestlink;
	
	# TODO BUG: %renderedfiles may not have it, if the linked to page
	# was also added and isn't yet rendered! Note that this bug is
	# masked by the bug that makes all new files be rendered twice.
	if (! grep { $_ eq $bestlink } values %renderedfiles) {
		$bestlink=htmlpage($bestlink);
	}
	if (! grep { $_ eq $bestlink } values %renderedfiles) {
		return "<span><a href=\"".
			cgiurl(do => "create", page => $link, from => $page).
			"\">?</a>$linktext</span>"
	}
	
	$bestlink=File::Spec->abs2rel($bestlink, dirname($page));
	
	if (! $noimageinline && isinlinableimage($bestlink)) {
		return "<img src=\"$bestlink\" alt=\"$linktext\" />";
	}
	return "<a href=\"$bestlink\">$linktext</a>";
} #}}}

sub indexlink () { #{{{
	return "<a href=\"$config{url}\">$config{wikiname}</a>";
} #}}}

sub lockwiki () { #{{{
	# Take an exclusive lock on the wiki to prevent multiple concurrent
	# run issues. The lock will be dropped on program exit.
	if (! -d $config{wikistatedir}) {
		mkdir($config{wikistatedir});
	}
	open(WIKILOCK, ">$config{wikistatedir}/lockfile") ||
		error ("cannot write to $config{wikistatedir}/lockfile: $!");
	if (! flock(WIKILOCK, 2 | 4)) {
		debug("wiki seems to be locked, waiting for lock");
		my $wait=600; # arbitrary, but don't hang forever to 
		              # prevent process pileup
		for (1..600) {
			return if flock(WIKILOCK, 2 | 4);
			sleep 1;
		}
		error("wiki is locked; waited $wait seconds without lock being freed (possible stuck process or stale lock?)");
	}
} #}}}

sub unlockwiki () { #{{{
	close WIKILOCK;
} #}}}

sub loadindex () { #{{{
	open (IN, "$config{wikistatedir}/index") || return;
	while (<IN>) {
		$_=possibly_foolish_untaint($_);
		chomp;
		my %items;
		$items{link}=[];
		foreach my $i (split(/ /, $_)) {
			my ($item, $val)=split(/=/, $i, 2);
			push @{$items{$item}}, $val;
		}

		next unless exists $items{src}; # skip bad lines for now

		my $page=pagename($items{src}[0]);
		if (! $config{rebuild}) {
			$pagesources{$page}=$items{src}[0];
			$oldpagemtime{$page}=$items{mtime}[0];
			$oldlinks{$page}=[@{$items{link}}];
			$links{$page}=[@{$items{link}}];
			$depends{$page}=join(" ", @{$items{depends}})
				if exists $items{depends};
			$renderedfiles{$page}=$items{dest}[0];
		}
		$pagectime{$page}=$items{ctime}[0];
	}
	close IN;
} #}}}

sub saveindex () { #{{{
	if (! -d $config{wikistatedir}) {
		mkdir($config{wikistatedir});
	}
	open (OUT, ">$config{wikistatedir}/index") || 
		error("cannot write to $config{wikistatedir}/index: $!");
	foreach my $page (keys %oldpagemtime) {
		next unless $oldpagemtime{$page};
		my $line="mtime=$oldpagemtime{$page} ".
			"ctime=$pagectime{$page} ".
			"src=$pagesources{$page} ".
			"dest=$renderedfiles{$page}";
		$line.=" link=$_" foreach @{$links{$page}};
		if (exists $depends{$page}) {
			$line.=" depends=$_" foreach split " ", $depends{$page};
		}
		print OUT $line."\n";
	}
	close OUT;
} #}}}

sub misctemplate ($$) { #{{{
	my $title=shift;
	my $pagebody=shift;
	
	my $template=HTML::Template->new(
		filename => "$config{templatedir}/misc.tmpl"
	);
	$template->param(
		title => $title,
		indexlink => indexlink(),
		wikiname => $config{wikiname},
		pagebody => $pagebody,
		styleurl => styleurl(),
		baseurl => "$config{url}/",
	);
	return $template->output;
}#}}}

sub glob_match ($$) { #{{{
	my $page=shift;
	my $glob=shift;

	# turn glob into safe regexp
	$glob=quotemeta($glob);
	$glob=~s/\\\*/.*/g;
	$glob=~s/\\\?/./g;
	$glob=~s!\\/!/!g;
	
	$page=~/^$glob$/i;
} #}}}

sub globlist_match ($$) { #{{{
	my $page=shift;
	my @globlist=split(" ", shift);

	# check any negated globs first
	foreach my $glob (@globlist) {
		return 0 if $glob=~/^!(.*)/ && glob_match($page, $1);
	}

	foreach my $glob (@globlist) {
		return 1 if glob_match($page, $glob);
	}
	
	return 0;
} #}}}

sub hook (@) { # {{{
	my %param=@_;
	
	if (! exists $param{type} || ! ref $param{call} || ! exists $param{id}) {
		error "hook requires type, call, and id parameters";
	}
	
	$hooks{$param{type}}{$param{id}}=\%param;
} # }}}

1
