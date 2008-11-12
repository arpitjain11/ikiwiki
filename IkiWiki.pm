#!/usr/bin/perl

package IkiWiki;
use warnings;
use strict;
use Encode;
use HTML::Entities;
use open qw{:utf8 :std};

use vars qw{%config %links %oldlinks %oldpagemtime %pagectime %pagecase
            %renderedfiles %oldrenderedfiles %pagesources %depends %hooks
	    %forcerebuild};

use Exporter q{import};
our @EXPORT = qw(hook debug error template htmlpage add_depends pagespec_match
                 bestlink htmllink readfile writefile pagetype srcfile pagename
                 displaytime will_render
                 %config %links %renderedfiles %pagesources);
our $VERSION = 1.01; # plugin interface version

# Optimisation.
use Memoize;
memoize("abs2rel");
memoize("pagespec_translate");

my $installdir=''; # INSTALLDIR_AUTOREPLACE done by Makefile, DNE
our $version='unknown'; # VERSION_AUTOREPLACE done by Makefile, DNE

sub defaultconfig () { #{{{
	wiki_file_prune_regexp => qr{((^|/).svn/|\.\.|^\.|\/\.|\.x?html?$|\.rss$|\.atom$|.arch-ids/|{arch}/)},
	wiki_link_regexp => qr/\[\[(?:([^\]\|]+)\|)?([^\s\]]+)\]\]/,
	wiki_file_regexp => qr/(^[-[:alnum:]_.:\/+]+$)/,
	verbose => 0,
	syslog => 0,
	wikiname => "wiki",
	default_pageext => "mdwn",
	cgi => 0,
	rcs => 'svn',
	notify => 0,
	url => '',
	cgiurl => '',
	historyurl => '',
	diffurl => '',
	anonok => 0,
	rss => 0,
	atom => 0,
	discussion => 1,
	rebuild => 0,
	refresh => 0,
	getctime => 0,
	w3mmode => 0,
	wrapper => undef,
	wrappermode => undef,
	svnrepo => undef,
	svnpath => "trunk",
	srcdir => undef,
	destdir => undef,
	pingurl => [],
	templatedir => "$installdir/share/ikiwiki/templates",
	underlaydir => "$installdir/share/ikiwiki/basewiki",
	setup => undef,
	adminuser => undef,
	adminemail => undef,
	plugin => [qw{mdwn inline htmlscrubber}],
	timeformat => '%c',
	locale => undef,
	sslcookie => 0,
	httpauth => 0,
} #}}}
   
sub checkconfig () { #{{{
	# locale stuff; avoid LC_ALL since it overrides everything
	if (defined $ENV{LC_ALL}) {
		$ENV{LANG} = $ENV{LC_ALL};
		delete $ENV{LC_ALL};
	}
	if (defined $config{locale}) {
		eval q{use POSIX};
		error($@) if $@;
		$ENV{LANG} = $config{locale}
			if POSIX::setlocale(&POSIX::LC_TIME, $config{locale});
	}

	if ($config{w3mmode}) {
		eval q{use Cwd q{abs_path}};
		error($@) if $@;
		$config{srcdir}=possibly_foolish_untaint(abs_path($config{srcdir}));
		$config{destdir}=possibly_foolish_untaint(abs_path($config{destdir}));
		$config{cgiurl}="file:///\$LIB/ikiwiki-w3m.cgi/".$config{cgiurl}
			unless $config{cgiurl} =~ m!file:///!;
		$config{url}="file://".$config{destdir};
	}

	if ($config{cgi} && ! length $config{url}) {
		error("Must specify url to wiki with --url when using --cgi\n");
	}
	if (($config{rss} || $config{atom}) && ! length $config{url}) {
		error("Must specify url to wiki with --url when using --rss or --atom\n");
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

	run_hooks(checkconfig => sub { shift->() });
} #}}}

sub loadplugins () { #{{{
	foreach my $plugin (@{$config{plugin}}) {
		my $mod="IkiWiki::Plugin::".possibly_foolish_untaint($plugin);
		eval qq{use $mod};
		if ($@) {
			error("Failed to load plugin $mod: $@");
		}
	}
	run_hooks(getopt => sub { shift->() });
	if (grep /^-/, @ARGV) {
		print STDERR "Unknown option: $_\n"
			foreach grep /^-/, @ARGV;
		usage();
	}
} #}}}

sub error ($) { #{{{
	if ($config{cgi}) {
		print "Content-type: text/html\n\n";
		print misctemplate("Error", "<p>Error: @_</p>");
	}
	log_message(error => @_);
	exit(1);
} #}}}

sub debug ($) { #{{{
	return unless $config{verbose};
	log_message(debug => @_);
} #}}}

my $log_open=0;
sub log_message ($$) { #{{{
	my $type=shift;

	if ($config{syslog}) {
		require Sys::Syslog;
		unless ($log_open) {
			Sys::Syslog::setlogsock('unix');
			Sys::Syslog::openlog('ikiwiki', '', 'user');
			$log_open=1;
		}
		eval {
			Sys::Syslog::syslog($type, join(" ", @_));
		}
	}
	elsif (! $config{cgi}) {
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
	
	if ($page =~ /\.([^.]+)$/) {
		return $1 if exists $hooks{htmlize}{$1};
	}
	return undef;
} #}}}

sub pagename ($) { #{{{
	my $file=shift;

	my $type=pagetype($file);
	my $page=$file;
	$page=~s/\Q.$type\E*$// if defined $type;
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
	binmode(IN) if ($binary);
	my $ret=<IN>;
	if (! utf8::valid($ret)) {
		$ret=encode_utf8($ret);
	}
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
	binmode(OUT) if ($binary);
	print OUT $content;
	close OUT;
} #}}}

my %cleared;
sub will_render ($$;$) { #{{{
	my $page=shift;
	my $dest=shift;
	my $clear=shift;

	# Important security check.
	if (-e "$config{destdir}/$dest" && ! $config{rebuild} &&
	    ! grep { $_ eq $dest } (@{$renderedfiles{$page}}, @{$oldrenderedfiles{$page}})) {
		error("$config{destdir}/$dest independently created, not overwriting with version from $page");
	}

	if (! $clear || $cleared{$page}) {
		$renderedfiles{$page}=[$dest, grep { $_ ne $dest } @{$renderedfiles{$page}}];
	}
	else {
		$renderedfiles{$page}=[$dest];
		$cleared{$page}=1;
	}
} #}}}

sub bestlink ($$) { #{{{
	my $page=shift;
	my $link=shift;
	
	my $cwd=$page;
	do {
		my $l=$cwd;
		$l.="/" if length $l;
		$l.=$link;

		if (exists $links{$l}) {
			return $l;
		}
		elsif (exists $pagecase{lc $l}) {
			return $pagecase{lc $l};
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

sub baseurl (;$) { #{{{
	my $page=shift;

	return "$config{url}/" if ! defined $page;
	
	$page=~s/[^\/]+$//;
	$page=~s/[^\/]+\//..\//g;
	return $page;
} #}}}

sub abs2rel ($$) { #{{{
	# Work around very innefficient behavior in File::Spec if abs2rel
	# is passed two relative paths. It's much faster if paths are
	# absolute! (Debian bug #376658)
	my $path="/".shift;
	my $base="/".shift;

	require File::Spec;
	my $ret=File::Spec->abs2rel($path, $base);
	$ret=~s/^// if defined $ret;
	return $ret;
} #}}}

sub displaytime ($) { #{{{
	my $time=shift;

	eval q{use POSIX};
	error($@) if $@;
	# strftime doesn't know about encodings, so make sure
	# its output is properly treated as utf8
	return decode_utf8(POSIX::strftime(
			$config{timeformat}, localtime($time)));
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
	
	return "<span class=\"selflink\">$linktext</span>"
		if length $bestlink && $page eq $bestlink;
	
	# TODO BUG: %renderedfiles may not have it, if the linked to page
	# was also added and isn't yet rendered! Note that this bug is
	# masked by the bug that makes all new files be rendered twice.
	if (! grep { $_ eq $bestlink } map { @{$_} } values %renderedfiles) {
		$bestlink=htmlpage($bestlink);
	}
	if (! grep { $_ eq $bestlink } map { @{$_} } values %renderedfiles) {
		return "<span><a href=\"".
			cgiurl(do => "create", page => lc($link), from => $page).
			"\">?</a>$linktext</span>"
	}
	
	$bestlink=abs2rel($bestlink, dirname($page));
	
	if (! $noimageinline && isinlinableimage($bestlink)) {
		return "<img src=\"$bestlink\" alt=\"$linktext\" />";
	}
	return "<a href=\"$bestlink\">$linktext</a>";
} #}}}

sub htmlize ($$$) { #{{{
	my $page=shift;
	my $type=shift;
	my $content=shift;

	if (exists $hooks{htmlize}{$type}) {
		$content=$hooks{htmlize}{$type}{call}->(
			page => $page,
			content => $content,
		);
	}
	else {
		error("htmlization of $type not supported");
	}

	run_hooks(sanitize => sub {
		$content=shift->(
			page => $page,
			content => $content,
		);
	});

	return $content;
} #}}}

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

my %preprocessing;
sub preprocess ($$$;$) { #{{{
	my $page=shift; # the page the data comes from
	my $destpage=shift; # the page the data will appear in (different for inline)
	my $content=shift;
	my $scan=shift;

	my $handle=sub {
		my $escape=shift;
		my $command=shift;
		my $params=shift;
		if (length $escape) {
			return "[[$command $params]]";
		}
		elsif (exists $hooks{preprocess}{$command}) {
			return "" if $scan && ! $hooks{preprocess}{$command}{scan};
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
			if ($preprocessing{$page}++ > 3) {
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

sub filter ($$) { #{{{
	my $page=shift;
	my $content=shift;

	run_hooks(filter => sub {
		$content=shift->(page => $page, content => $content);
	});

	return $content;
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
		$items{dest}=[];
		foreach my $i (split(/ /, $_)) {
			my ($item, $val)=split(/=/, $i, 2);
			push @{$items{$item}}, decode_entities($val);
		}

		next unless exists $items{src}; # skip bad lines for now

		my $page=pagename($items{src}[0]);
		if (! $config{rebuild}) {
			$pagesources{$page}=$items{src}[0];
			$oldpagemtime{$page}=$items{mtime}[0];
			$oldlinks{$page}=[@{$items{link}}];
			$links{$page}=[@{$items{link}}];
			$depends{$page}=$items{depends}[0] if exists $items{depends};
			$renderedfiles{$page}=[@{$items{dest}}];
			$oldrenderedfiles{$page}=[@{$items{dest}}];
			$pagecase{lc $page}=$page;
		}
		$pagectime{$page}=$items{ctime}[0];
	}
	close IN;
} #}}}

sub saveindex () { #{{{
	run_hooks(savestate => sub { shift->() });

	if (! -d $config{wikistatedir}) {
		mkdir($config{wikistatedir});
	}
	open (OUT, ">$config{wikistatedir}/index") || 
		error("cannot write to $config{wikistatedir}/index: $!");
	foreach my $page (keys %oldpagemtime) {
		next unless $oldpagemtime{$page};
		my $line="mtime=$oldpagemtime{$page} ".
			"ctime=$pagectime{$page} ".
			"src=$pagesources{$page}";
		$line.=" dest=$_" foreach @{$renderedfiles{$page}};
		my %count;
		$line.=" link=$_" foreach grep { ++$count{$_} == 1 } @{$links{$page}};
		if (exists $depends{$page}) {
			$line.=" depends=".encode_entities($depends{$page}, " \t\n");
		}
		print OUT $line."\n";
	}
	close OUT;
} #}}}

sub template_params (@) { #{{{
	my $filename=shift;
	
	require HTML::Template;
	return filter => sub {
			my $text_ref = shift;
			$$text_ref=&Encode::decode_utf8($$text_ref);
		},
		filename => "$config{templatedir}/$filename",
		loop_context_vars => 1,
		die_on_bad_params => 0,
		@_;
} #}}}

sub template ($;@) { #{{{
	HTML::Template->new(template_params(@_));
} #}}}

sub misctemplate ($$;@) { #{{{
	my $title=shift;
	my $pagebody=shift;
	
	my $template=template("misc.tmpl");
	$template->param(
		title => $title,
		indexlink => indexlink(),
		wikiname => $config{wikiname},
		pagebody => $pagebody,
		baseurl => baseurl(),
		@_,
	);
	run_hooks(pagetemplate => sub {
		shift->(page => "", destpage => "", template => $template);
	});
	return $template->output;
}#}}}

sub hook (@) { # {{{
	my %param=@_;
	
	if (! exists $param{type} || ! ref $param{call} || ! exists $param{id}) {
		error "hook requires type, call, and id parameters";
	}

	return if $param{no_override} && exists $hooks{$param{type}}{$param{id}};
	
	$hooks{$param{type}}{$param{id}}=\%param;
} # }}}

sub run_hooks ($$) { # {{{
	# Calls the given sub for each hook of the given type,
	# passing it the hook function to call.
	my $type=shift;
	my $sub=shift;

	if (exists $hooks{$type}) {
		foreach my $id (keys %{$hooks{$type}}) {
			$sub->($hooks{$type}{$id}{call});
		}
	}
} #}}}

sub globlist_to_pagespec ($) { #{{{
	my @globlist=split(' ', shift);

	my (@spec, @skip);
	foreach my $glob (@globlist) {
		if ($glob=~/^!(.*)/) {
			push @skip, $glob;
		}
		else {
			push @spec, $glob;
		}
	}

	my $spec=join(" or ", @spec);
	if (@skip) {
		my $skip=join(" and ", @skip);
		if (length $spec) {
			$spec="$skip and ($spec)";
		}
		else {
			$spec=$skip;
		}
	}
	return $spec;
} #}}}

sub is_globlist ($) { #{{{
	my $s=shift;
	$s=~/[^\s]+\s+([^\s]+)/ && $1 ne "and" && $1 ne "or";
} #}}}

sub safequote ($) { #{{{
	my $s=shift;
	$s=~s/[{}]//g;
	return "q{$s}";
} #}}}

sub pagespec_merge ($$) { #{{{
	my $a=shift;
	my $b=shift;

	return $a if $a eq $b;

        # Support for old-style GlobLists.
        if (is_globlist($a)) {
                $a=globlist_to_pagespec($a);
        }
        if (is_globlist($b)) {
                $b=globlist_to_pagespec($b);
        }

	return "($a) or ($b)";
} #}}}

sub pagespec_translate ($) { #{{{
	# This assumes that $page is in scope in the function
	# that evalulates the translated pagespec code.
	my $spec=shift;

	# Support for old-style GlobLists.
	if (is_globlist($spec)) {
		$spec=globlist_to_pagespec($spec);
	}

	# Convert spec to perl code.
	my $code="";
	while ($spec=~m/\s*(\!|\(|\)|\w+\([^\)]+\)|[^\s()]+)\s*/ig) {
		my $word=$1;
		if (lc $word eq "and") {
			$code.=" &&";
		}
		elsif (lc $word eq "or") {
			$code.=" ||";
		}
		elsif ($word eq "(" || $word eq ")" || $word eq "!") {
			$code.=" ".$word;
		}
		elsif ($word =~ /^(link|backlink|created_before|created_after|creation_month|creation_year|creation_day)\((.+)\)$/) {
			$code.=" match_$1(\$page, ".safequote($2).")";
		}
		else {
			$code.=" match_glob(\$page, ".safequote($word).")";
		}
	}

	return $code;
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

sub pagespec_match ($$) { #{{{
	my $page=shift;
	my $spec=shift;

	return eval pagespec_translate($spec);
} #}}}

sub match_glob ($$) { #{{{
	my $page=shift;
	my $glob=shift;

	# turn glob into safe regexp
	$glob=quotemeta($glob);
	$glob=~s/\\\*/.*/g;
	$glob=~s/\\\?/./g;

	return $page=~/^$glob$/i;
} #}}}

sub match_link ($$) { #{{{
	my $page=shift;
	my $link=lc(shift);

	my $links = $links{$page} or return undef;
	foreach my $p (@$links) {
		return 1 if lc $p eq $link;
	}
	return 0;
} #}}}

sub match_backlink ($$) { #{{{
	match_link(pop, pop);
} #}}}

sub match_created_before ($$) { #{{{
	my $page=shift;
	my $testpage=shift;

	if (exists $pagectime{$testpage}) {
		return $pagectime{$page} < $pagectime{$testpage};
	}
	else {
		return 0;
	}
} #}}}

sub match_created_after ($$) { #{{{
	my $page=shift;
	my $testpage=shift;

	if (exists $pagectime{$testpage}) {
		return $pagectime{$page} > $pagectime{$testpage};
	}
	else {
		return 0;
	}
} #}}}

sub match_creation_day ($$) { #{{{
	return ((gmtime($pagectime{shift()}))[3] == shift);
} #}}}

sub match_creation_month ($$) { #{{{
	return ((gmtime($pagectime{shift()}))[4] + 1 == shift);
} #}}}

sub match_creation_year ($$) { #{{{
	return ((gmtime($pagectime{shift()}))[5] + 1900 == shift);
} #}}}

1
