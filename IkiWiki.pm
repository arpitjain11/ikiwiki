#!/usr/bin/perl

package IkiWiki;
use warnings;
use strict;
use Encode;
use HTML::Entities;
use URI::Escape q{uri_escape_utf8};
use POSIX;
use open qw{:utf8 :std};

use vars qw{%config %links %oldlinks %pagemtime %pagectime %pagecase
            %renderedfiles %oldrenderedfiles %pagesources %destsources
	    %depends %hooks %forcerebuild $gettext_obj};

use Exporter q{import};
our @EXPORT = qw(hook debug error template htmlpage add_depends pagespec_match
                 bestlink htmllink readfile writefile pagetype srcfile pagename
                 displaytime will_render gettext urlto targetpage
                 %config %links %renderedfiles %pagesources);
our $VERSION = 1.02; # plugin interface version, next is ikiwiki version
our $version='unknown'; # VERSION_AUTOREPLACE done by Makefile, DNE
my $installdir=''; # INSTALLDIR_AUTOREPLACE done by Makefile, DNE

# Optimisation.
use Memoize;
memoize("abs2rel");
memoize("pagespec_translate");
memoize("file_pruned");

sub defaultconfig () { #{{{
	wiki_file_prune_regexps => [qr/\.\./, qr/^\./, qr/\/\./,
		qr/\.x?html?$/, qr/\.ikiwiki-new$/,
		qr/(^|\/).svn\//, qr/.arch-ids\//, qr/{arch}\//],
	wiki_link_regexp => qr/\[\[(?:([^\]\|]+)\|)?([^\s\]#]+)(?:#([^\s\]]+))?\]\]/,
	wiki_file_regexp => qr/(^[-[:alnum:]_.:\/+]+$)/,
	web_commit_regexp => qr/^web commit (by (.*?(?=: |$))|from (\d+\.\d+\.\d+\.\d+)):?(.*)/,
	verbose => 0,
	syslog => 0,
	wikiname => "wiki",
	default_pageext => "mdwn",
	cgi => 0,
	post_commit => 0,
	rcs => '',
	notify => 0,
	url => '',
	cgiurl => '',
	historyurl => '',
	diffurl => '',
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
	gitorigin_branch => "origin",
	gitmaster_branch => "master",
	srcdir => undef,
	destdir => undef,
	pingurl => [],
	templatedir => "$installdir/share/ikiwiki/templates",
	underlaydir => "$installdir/share/ikiwiki/basewiki",
	setup => undef,
	adminuser => undef,
	adminemail => undef,
	plugin => [qw{mdwn inline htmlscrubber passwordauth signinedit
	              lockedit conditional}],
	timeformat => '%c',
	locale => undef,
	sslcookie => 0,
	httpauth => 0,
	userdir => "",
	usedirs => 0,
	numbacklinks => 10,
} #}}}
   
sub checkconfig () { #{{{
	# locale stuff; avoid LC_ALL since it overrides everything
	if (defined $ENV{LC_ALL}) {
		$ENV{LANG} = $ENV{LC_ALL};
		delete $ENV{LC_ALL};
	}
	if (defined $config{locale}) {
		if (POSIX::setlocale(&POSIX::LC_ALL, $config{locale})) {
			$ENV{LANG}=$config{locale};
			$gettext_obj=undef;
		}
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
		error(gettext("Must specify url to wiki with --url when using --cgi"));
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
	loadplugin($_) foreach @{$config{plugin}};
	
	run_hooks(getopt => sub { shift->() });
	if (grep /^-/, @ARGV) {
		print STDERR "Unknown option: $_\n"
			foreach grep /^-/, @ARGV;
		usage();
	}
} #}}}

sub loadplugin ($) { #{{{
	my $plugin=shift;

	return if grep { $_ eq $plugin} @{$config{disable_plugins}};

	my $mod="IkiWiki::Plugin::".possibly_foolish_untaint($plugin);
	eval qq{use $mod};
	if ($@) {
		error("Failed to load plugin $mod: $@");
	}
} #}}}

sub error ($;$) { #{{{
	my $message=shift;
	my $cleaner=shift;
	if ($config{cgi}) {
		print "Content-type: text/html\n\n";
		print misctemplate(gettext("Error"),
			"<p>".gettext("Error").": $message</p>");
	}
	log_message('err' => $message) if $config{syslog};
	if (defined $cleaner) {
		$cleaner->();
	}
	die $message."\n";
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
			Sys::Syslog::syslog($type, "%s", join(" ", @_));
		};
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

sub targetpage ($$) { #{{{
	my $page=shift;
	my $ext=shift;
	
	if (! $config{usedirs} || $page =~ /^index$/ ) {
		return $page.".".$ext;
	} else {
		return $page."/index.".$ext;
	}
} #}}}

sub htmlpage ($) { #{{{
	my $page=shift;
	
	return targetpage($page, "html");
} #}}}

sub srcfile ($) { #{{{
	my $file=shift;

	return "$config{srcdir}/$file" if -e "$config{srcdir}/$file";
	return "$config{underlaydir}/$file" if -e "$config{underlaydir}/$file";
	error("internal error: $file cannot be found");
} #}}}

sub readfile ($;$$) { #{{{
	my $file=shift;
	my $binary=shift;
	my $wantfd=shift;

	if (-l $file) {
		error("cannot read a symlink ($file)");
	}
	
	local $/=undef;
	open (IN, $file) || error("failed to read $file: $!");
	binmode(IN) if ($binary);
	return \*IN if $wantfd;
	my $ret=<IN>;
	close IN || error("failed to read $file: $!");
	return $ret;
} #}}}

sub writefile ($$$;$$) { #{{{
	my $file=shift; # can include subdirs
	my $destdir=shift; # directory to put file in
	my $content=shift;
	my $binary=shift;
	my $writer=shift;
	
	my $test=$file;
	while (length $test) {
		if (-l "$destdir/$test") {
			error("cannot write to a symlink ($test)");
		}
		$test=dirname($test);
	}
	my $newfile="$destdir/$file.ikiwiki-new";
	if (-l $newfile) {
		error("cannot write to a symlink ($newfile)");
	}

	my $dir=dirname($newfile);
	if (! -d $dir) {
		my $d="";
		foreach my $s (split(m!/+!, $dir)) {
			$d.="$s/";
			if (! -d $d) {
				mkdir($d) || error("failed to create directory $d: $!");
			}
		}
	}

	my $cleanup = sub { unlink($newfile) };
	open (OUT, ">$newfile") || error("failed to write $newfile: $!", $cleanup);
	binmode(OUT) if ($binary);
	if ($writer) {
		$writer->(\*OUT, $cleanup);
	}
	else {
		print OUT $content or error("failed writing to $newfile: $!", $cleanup);
	}
	close OUT || error("failed saving $newfile: $!", $cleanup);
	rename($newfile, "$destdir/$file") || 
		error("failed renaming $newfile to $destdir/$file: $!", $cleanup);
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
		foreach my $old (@{$renderedfiles{$page}}) {
			delete $destsources{$old};
		}
		$renderedfiles{$page}=[$dest];
		$cleared{$page}=1;
	}
	$destsources{$dest}=$page;
} #}}}

sub bestlink ($$) { #{{{
	my $page=shift;
	my $link=shift;
	
	my $cwd=$page;
	if ($link=~s/^\/+//) {
		# absolute links
		$cwd="";
	}

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

	if (length $config{userdir} && exists $links{"$config{userdir}/".lc($link)}) {
		return "$config{userdir}/".lc($link);
	}

	#print STDERR "warning: page $page, broken link: $link\n";
	return "";
} #}}}

sub isinlinableimage ($) { #{{{
	my $file=shift;
	
	$file=~/\.(png|gif|jpg|jpeg)$/i;
} #}}}

sub pagetitle ($;$) { #{{{
	my $page=shift;
	my $unescaped=shift;

	if ($unescaped) {
		$page=~s/(__(\d+)__|_)/$1 eq '_' ? ' ' : chr($2)/eg;
	}
	else {
		$page=~s/(__(\d+)__|_)/$1 eq '_' ? ' ' : "&#$2;"/eg;
	}

	return $page;
} #}}}

sub titlepage ($) { #{{{
	my $title=shift;
	$title=~s/([^-[:alnum:]:+\/.])/$1 eq ' ' ? '_' : "__".ord($1)."__"/eg;
	return $title;
} #}}}

sub linkpage ($) { #{{{
	my $link=shift;
	$link=~s/([^-[:alnum:]:+\/._])/$1 eq ' ' ? '_' : "__".ord($1)."__"/eg;
	return $link;
} #}}}

sub cgiurl (@) { #{{{
	my %params=@_;

	return $config{cgiurl}."?".
		join("&amp;", map $_."=".uri_escape_utf8($params{$_}), keys %params);
} #}}}

sub baseurl (;$) { #{{{
	my $page=shift;

	return "$config{url}/" if ! defined $page;
	
	$page=htmlpage($page);
	$page=~s/[^\/]+$//;
	$page=~s/[^\/]+\//..\//g;
	return $page;
} #}}}

sub abs2rel ($$) { #{{{
	# Work around very innefficient behavior in File::Spec if abs2rel
	# is passed two relative paths. It's much faster if paths are
	# absolute! (Debian bug #376658; fixed in debian unstable now)
	my $path="/".shift;
	my $base="/".shift;

	require File::Spec;
	my $ret=File::Spec->abs2rel($path, $base);
	$ret=~s/^// if defined $ret;
	return $ret;
} #}}}

sub displaytime ($) { #{{{
	my $time=shift;

	# strftime doesn't know about encodings, so make sure
	# its output is properly treated as utf8
	return decode_utf8(POSIX::strftime(
			$config{timeformat}, localtime($time)));
} #}}}

sub beautify_url ($) { #{{{
	my $url=shift;

	$url =~ s!/index.html$!/!;
	$url =~ s!^$!./!; # Browsers don't like empty links...

	return $url;
} #}}}

sub urlto ($$) { #{{{
	my $to=shift;
	my $from=shift;

	if (! length $to) {
		return beautify_url(baseurl($from));
	}

	if (! $destsources{$to}) {
		$to=htmlpage($to);
	}

	my $link = abs2rel($to, dirname(htmlpage($from)));

	return beautify_url($link);
} #}}}

sub htmllink ($$$;@) { #{{{
	my $lpage=shift; # the page doing the linking
	my $page=shift; # the page that will contain the link (different for inline)
	my $link=shift;
	my %opts=@_;

	my $bestlink;
	if (! $opts{forcesubpage}) {
		$bestlink=bestlink($lpage, $link);
	}
	else {
		$bestlink="$lpage/".lc($link);
	}

	my $linktext;
	if (defined $opts{linktext}) {
		$linktext=$opts{linktext};
	}
	else {
		$linktext=pagetitle(basename($link));
	}
	
	return "<span class=\"selflink\">$linktext</span>"
		if length $bestlink && $page eq $bestlink;
	
	if (! $destsources{$bestlink}) {
		$bestlink=htmlpage($bestlink);

		if (! $destsources{$bestlink}) {
			return $linktext unless length $config{cgiurl};
			return "<span><a href=\"".
				cgiurl(
					do => "create",
					page => pagetitle(lc($link), 1),
					from => $lpage
				).
				"\">?</a>$linktext</span>"
		}
	}
	
	$bestlink=abs2rel($bestlink, dirname(htmlpage($page)));
	$bestlink=beautify_url($bestlink);
	
	if (! $opts{noimageinline} && isinlinableimage($bestlink)) {
		return "<img src=\"$bestlink\" alt=\"$linktext\" />";
	}

	if (defined $opts{anchor}) {
		$bestlink.="#".$opts{anchor};
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
		defined $2
			? ( $1 
				? "[[$2|$3".($4 ? "#$4" : "")."]]" 
				: htmllink($lpage, $page, linkpage($3),
					anchor => $4, linktext => pagetitle($2)))
			: ( $1 
				? "[[$3".($4 ? "#$4" : "")."]]"
				: htmllink($lpage, $page, linkpage($3),
					anchor => $4))
	}eg;
	
	return $content;
} #}}}

my %preprocessing;
our $preprocess_preview=0;
sub preprocess ($$$;$$) { #{{{
	my $page=shift; # the page the data comes from
	my $destpage=shift; # the page the data will appear in (different for inline)
	my $content=shift;
	my $scan=shift;
	my $preview=shift;

	# Using local because it needs to be set within any nested calls
	# of this function.
	local $preprocess_preview=$preview if defined $preview;

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
				#translators: The first parameter is a
				#translators: preprocessor directive name,
				#translators: the second a page name, the
				#translators: third a number.
				return "[[".sprintf(gettext("%s preprocessing loop detected on %s at depth %i"),
					$command, $page, $preprocessing{$page}).
				"]]";
			}
			my $ret=$hooks{preprocess}{$command}{call}->(
				@params,
				page => $page,
				destpage => $destpage,
				preview => $preprocess_preview,
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
	if (! flock(WIKILOCK, 2 | 4)) { # LOCK_EX | LOCK_NB
		debug("wiki seems to be locked, waiting for lock");
		my $wait=600; # arbitrary, but don't hang forever to 
		              # prevent process pileup
		for (1..$wait) {
			return if flock(WIKILOCK, 2 | 4);
			sleep 1;
		}
		error("wiki is locked; waited $wait seconds without lock being freed (possible stuck process or stale lock?)");
	}
} #}}}

sub unlockwiki () { #{{{
	close WIKILOCK;
} #}}}

sub commit_hook_enabled () { #{{{
	open(COMMITLOCK, "+>$config{wikistatedir}/commitlock") ||
		error ("cannot write to $config{wikistatedir}/commitlock: $!");
	if (! flock(COMMITLOCK, 1 | 4)) { # LOCK_SH | LOCK_NB to test
		close COMMITLOCK;
		return 0;
	}
	close COMMITLOCK;
	return 1;
} #}}}

sub disable_commit_hook () { #{{{
	open(COMMITLOCK, ">$config{wikistatedir}/commitlock") ||
		error ("cannot write to $config{wikistatedir}/commitlock: $!");
	if (! flock(COMMITLOCK, 2)) { # LOCK_EX
		error("failed to get commit lock");
	}
} #}}}

sub enable_commit_hook () { #{{{
	close COMMITLOCK;
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
			$pagemtime{$page}=$items{mtime}[0];
			$oldlinks{$page}=[@{$items{link}}];
			$links{$page}=[@{$items{link}}];
			$depends{$page}=$items{depends}[0] if exists $items{depends};
			$destsources{$_}=$page foreach @{$items{dest}};
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
	my $newfile="$config{wikistatedir}/index.new";
	my $cleanup = sub { unlink($newfile) };
	open (OUT, ">$newfile") || error("cannot write to $newfile: $!", $cleanup);
	foreach my $page (keys %pagemtime) {
		next unless $pagemtime{$page};
		my $line="mtime=$pagemtime{$page} ".
			"ctime=$pagectime{$page} ".
			"src=$pagesources{$page}";
		$line.=" dest=$_" foreach @{$renderedfiles{$page}};
		my %count;
		$line.=" link=$_" foreach grep { ++$count{$_} == 1 } @{$links{$page}};
		if (exists $depends{$page}) {
			$line.=" depends=".encode_entities($depends{$page}, " \t\n");
		}
		print OUT $line."\n" || error("failed writing to $newfile: $!", $cleanup);
	}
	close OUT || error("failed saving to $newfile: $!", $cleanup);
	rename($newfile, "$config{wikistatedir}/index") ||
		error("failed renaming $newfile to $config{wikistatedir}/index", $cleanup);
} #}}}

sub template_file ($) { #{{{
	my $template=shift;

	foreach my $dir ($config{templatedir}, "$installdir/share/ikiwiki/templates") {
		return "$dir/$template" if -e "$dir/$template";
	}
	return undef;
} #}}}

sub template_params (@) { #{{{
	my $filename=template_file(shift);

	if (! defined $filename) {
		return if wantarray;
		return "";
	}

	require HTML::Template;
	my @ret=(
		filter => sub {
			my $text_ref = shift;
			$$text_ref=&Encode::decode_utf8($$text_ref);
		},
		filename => $filename,
		loop_context_vars => 1,
		die_on_bad_params => 0,
		@_
	);
	return wantarray ? @ret : {@ret};
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
		my @deferred;
		foreach my $id (keys %{$hooks{$type}}) {
			if ($hooks{$type}{$id}{last}) {
				push @deferred, $id;
				next;
			}
			$sub->($hooks{$type}{$id}{call});
		}
		foreach my $id (@deferred) {
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

sub file_pruned ($$) { #{{{
	require File::Spec;
	my $file=File::Spec->canonpath(shift);
	my $base=File::Spec->canonpath(shift);
	$file=~s#^\Q$base\E/*##;

	my $regexp='('.join('|', @{$config{wiki_file_prune_regexps}}).')';
	$file =~ m/$regexp/;
} #}}}

sub gettext { #{{{
	# Only use gettext in the rare cases it's needed.
	if (exists $ENV{LANG} || exists $ENV{LC_ALL} || exists $ENV{LC_MESSAGES}) {
		if (! $gettext_obj) {
			$gettext_obj=eval q{
				use Locale::gettext q{textdomain};
				Locale::gettext->domain('ikiwiki')
			};
			if ($@) {
				print STDERR "$@";
				$gettext_obj=undef;
				return shift;
			}
		}
		return $gettext_obj->get(shift);
	}
	else {
		return shift;
	}
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
		elsif ($word =~ /^(\w+)\((.*)\)$/) {
			if (exists $IkiWiki::PageSpec::{"match_$1"}) {
				$code.="IkiWiki::PageSpec::match_$1(\$page, ".safequote($2).", \$from)";
			}
			else {
				$code.=" 0";
			}
		}
		else {
			$code.=" IkiWiki::PageSpec::match_glob(\$page, ".safequote($word).", \$from)";
		}
	}

	return $code;
} #}}}

sub pagespec_match ($$;$) { #{{{
	my $page=shift;
	my $spec=shift;
	my $from=shift;

	return eval pagespec_translate($spec);
} #}}}

package IkiWiki::PageSpec;

sub match_glob ($$$) { #{{{
	my $page=shift;
	my $glob=shift;
	my $from=shift;
	if (! defined $from){
		$from = "";
	}

	# relative matching
	if ($glob =~ m!^\./!) {
		$from=~s!/?[^/]+$!!;
		$glob=~s!^\./!!;
		$glob="$from/$glob" if length $from;
	}

	# turn glob into safe regexp
	$glob=quotemeta($glob);
	$glob=~s/\\\*/.*/g;
	$glob=~s/\\\?/./g;

	return $page=~/^$glob$/i;
} #}}}

sub match_link ($$$) { #{{{
	my $page=shift;
	my $link=lc(shift);
	my $from=shift;
	if (! defined $from){
		$from = "";
	}

	# relative matching
	if ($link =~ m!^\.! && defined $from) {
		$from=~s!/?[^/]+$!!;
		$link=~s!^\./!!;
		$link="$from/$link" if length $from;
	}

	my $links = $IkiWiki::links{$page} or return undef;
	return 0 unless @$links;
	my $bestlink = IkiWiki::bestlink($from, $link);
	return 0 unless length $bestlink;
	foreach my $p (@$links) {
		return 1 if $bestlink eq IkiWiki::bestlink($page, $p);
	}
	return 0;
} #}}}

sub match_backlink ($$$) { #{{{
	match_link($_[1], $_[0], $_[3]);
} #}}}

sub match_created_before ($$$) { #{{{
	my $page=shift;
	my $testpage=shift;

	if (exists $IkiWiki::pagectime{$testpage}) {
		return $IkiWiki::pagectime{$page} < $IkiWiki::pagectime{$testpage};
	}
	else {
		return 0;
	}
} #}}}

sub match_created_after ($$$) { #{{{
	my $page=shift;
	my $testpage=shift;

	if (exists $IkiWiki::pagectime{$testpage}) {
		return $IkiWiki::pagectime{$page} > $IkiWiki::pagectime{$testpage};
	}
	else {
		return 0;
	}
} #}}}

sub match_creation_day ($$$) { #{{{
	return ((gmtime($IkiWiki::pagectime{shift()}))[3] == shift);
} #}}}

sub match_creation_month ($$$) { #{{{
	return ((gmtime($IkiWiki::pagectime{shift()}))[4] + 1 == shift);
} #}}}

sub match_creation_year ($$$) { #{{{
	return ((gmtime($IkiWiki::pagectime{shift()}))[5] + 1900 == shift);
} #}}}

1
