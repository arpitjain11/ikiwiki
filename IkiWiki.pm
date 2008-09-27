#!/usr/bin/perl

package IkiWiki;

use warnings;
use strict;
use Encode;
use HTML::Entities;
use URI::Escape q{uri_escape_utf8};
use POSIX;
use Storable;
use open qw{:utf8 :std};

use vars qw{%config %links %oldlinks %pagemtime %pagectime %pagecase
	    %pagestate %renderedfiles %oldrenderedfiles %pagesources
	    %destsources %depends %hooks %forcerebuild $gettext_obj
	    %loaded_plugins};

use Exporter q{import};
our @EXPORT = qw(hook debug error template htmlpage add_depends pagespec_match
                 bestlink htmllink readfile writefile pagetype srcfile pagename
                 displaytime will_render gettext urlto targetpage
		 add_underlay pagetitle titlepage linkpage
                 %config %links %pagestate %renderedfiles
                 %pagesources %destsources);
our $VERSION = 2.00; # plugin interface version, next is ikiwiki version
our $version='unknown'; # VERSION_AUTOREPLACE done by Makefile, DNE
my $installdir=''; # INSTALLDIR_AUTOREPLACE done by Makefile, DNE

# Optimisation.
use Memoize;
memoize("abs2rel");
memoize("pagespec_translate");
memoize("file_pruned");

sub getsetup () { #{{{
	wikiname => {
		type => "string",
		default => "wiki",
		description => "name of the wiki",
		safe => 1,
		rebuild => 1,
	},
	adminemail => {
		type => "string",
		default => undef,
		example => 'me@example.com',
		description => "contact email for wiki",
		safe => 1,
		rebuild => 0,
	},
	adminuser => {
		type => "string",
		default => [],
		description => "users who are wiki admins",
		safe => 1,
		rebuild => 0,
	},
	banned_users => {
		type => "string",
		default => [],
		description => "users who are banned from the wiki",
		safe => 1,
		rebuild => 0,
	},
	srcdir => {
		type => "string",
		default => undef,
		example => "$ENV{HOME}/wiki",
		description => "where the source of the wiki is located",
		safe => 0, # path
		rebuild => 1,
	},
	destdir => {
		type => "string",
		default => undef,
		example => "/var/www/wiki",
		description => "where to build the wiki",
		safe => 0, # path
		rebuild => 1,
	},
	url => {
		type => "string",
		default => '',
		example => "http://example.com/wiki",
		description => "base url to the wiki",
		safe => 1,
		rebuild => 1,
	},
	cgiurl => {
		type => "string",
		default => '',
		example => "http://example.com/wiki/ikiwiki.cgi",
		description => "url to the ikiwiki.cgi",
		safe => 1,
		rebuild => 1,
	},
	cgi_wrapper => {
		type => "string",
		default => '',
		example => "/var/www/wiki/ikiwiki.cgi",
		description => "cgi wrapper to generate",
		safe => 0, # file
		rebuild => 0,
	},
	cgi_wrappermode => {
		type => "string",
		default => '06755',
		description => "mode for cgi_wrapper (can safely be made suid)",
		safe => 0,
		rebuild => 0,
	},
	rcs => {
		type => "string",
		default => '',
		description => "rcs backend to use",
		safe => 0, # don't allow overriding
		rebuild => 0,
	},
	default_plugins => {
		type => "internal",
		default => [qw{mdwn link inline htmlscrubber passwordauth
				openid signinedit lockedit conditional
				recentchanges parentlinks editpage}],
		description => "plugins to enable by default",
		safe => 0,
		rebuild => 1,
	},
	add_plugins => {
		type => "string",
		default => [],
		description => "plugins to add to the default configuration",
		safe => 1,
		rebuild => 1,
	},
	disable_plugins => {
		type => "string",
		default => [],
		description => "plugins to disable",
		safe => 1,
		rebuild => 1,
	},
	templatedir => {
		type => "string",
		default => "$installdir/share/ikiwiki/templates",
		description => "location of template files",
		advanced => 1,
		safe => 0, # path
		rebuild => 1,
	},
	underlaydir => {
		type => "string",
		default => "$installdir/share/ikiwiki/basewiki",
		description => "base wiki source location",
		advanced => 1,
		safe => 0, # path
		rebuild => 0,
	},
	wrappers => {
		type => "internal",
		default => [],
		description => "wrappers to generate",
		safe => 0,
		rebuild => 0,
	},
	underlaydirs => {
		type => "internal",
		default => [],
		description => "additional underlays to use",
		safe => 0,
		rebuild => 0,
	},
	verbose => {
		type => "boolean",
		example => 1,
		description => "display verbose messages when building?",
		safe => 1,
		rebuild => 0,
	},
	syslog => {
		type => "boolean",
		example => 1,
		description => "log to syslog?",
		safe => 1,
		rebuild => 0,
	},
	usedirs => {
		type => "boolean",
		default => 1,
		description => "create output files named page/index.html?",
		safe => 0, # changing requires manual transition
		rebuild => 1,
	},
	prefix_directives => {
		type => "boolean",
		default => 0,
		description => "use '!'-prefixed preprocessor directives?",
		safe => 0, # changing requires manual transition
		rebuild => 1,
	},
	discussion => {
		type => "boolean",
		default => 1,
		description => "enable Discussion pages?",
		safe => 1,
		rebuild => 1,
	},
	sslcookie => {
		type => "boolean",
		default => 0,
		description => "only send cookies over SSL connections?",
		advanced => 1,
		safe => 1,
		rebuild => 0,
	},
	default_pageext => {
		type => "string",
		default => "mdwn",
		description => "extension to use for new pages",
		safe => 0, # not sanitized
		rebuild => 0,
	},
	htmlext => {
		type => "string",
		default => "html",
		description => "extension to use for html files",
		safe => 0, # not sanitized
		rebuild => 1,
	},
	timeformat => {
		type => "string",
		default => '%c',
		description => "strftime format string to display date",
		advanced => 1,
		safe => 1,
		rebuild => 1,
	},
	locale => {
		type => "string",
		default => undef,
		example => "en_US.UTF-8",
		description => "UTF-8 locale to use",
		advanced => 1,
		safe => 0,
		rebuild => 1,
	},
	userdir => {
		type => "string",
		default => "",
		example => "users",
		description => "put user pages below specified page",
		safe => 1,
		rebuild => 1,
	},
	numbacklinks => {
		type => "integer",
		default => 10,
		description => "how many backlinks to show before hiding excess (0 to show all)",
		safe => 1,
		rebuild => 1,
	},
	hardlink => {
		type => "boolean",
		default => 0,
		description => "attempt to hardlink source files? (optimisation for large files)",
		advanced => 1,
		safe => 0, # paranoia
		rebuild => 0,
	},
	umask => {
		type => "integer",
		description => "",
		example => "022",
		description => "force ikiwiki to use a particular umask",
		advanced => 1,
		safe => 0, # paranoia
		rebuild => 0,
	},
	libdir => {
		type => "string",
		default => "",
		example => "$ENV{HOME}/.ikiwiki/",
		description => "extra library and plugin directory",
		advanced => 1,
		safe => 0, # directory
		rebuild => 0,
	},
	ENV => {
		type => "string", 
		default => {},
		description => "environment variables",
		safe => 0, # paranoia
		rebuild => 0,
	},
	exclude => {
		type => "string",
		default => undef,
		example => '\.wav$',
		description => "regexp of source files to ignore",
		advanced => 1,
		safe => 0, # regexp
		rebuild => 1,
	},
	wiki_file_prune_regexps => {
		type => "internal",
		default => [qr/(^|\/)\.\.(\/|$)/, qr/^\./, qr/\/\./,
			qr/\.x?html?$/, qr/\.ikiwiki-new$/,
			qr/(^|\/).svn\//, qr/.arch-ids\//, qr/{arch}\//,
			qr/(^|\/)_MTN\//,
			qr/\.dpkg-tmp$/],
		description => "regexps of source files to ignore",
		safe => 0,
		rebuild => 1,
	},
	wiki_file_chars => {
		type => "string",
		description => "specifies the characters that are allowed in source filenames",
		default => "-[:alnum:]+/.:_",
		safe => 0,
		rebuild => 1,
	},
	wiki_file_regexp => {
		type => "internal",
		description => "regexp of legal source files",
		safe => 0,
		rebuild => 1,
	},
	web_commit_regexp => {
		type => "internal",
		default => qr/^web commit (by (.*?(?=: |$))|from (\d+\.\d+\.\d+\.\d+)):?(.*)/,
		description => "regexp to parse web commits from logs",
		safe => 0,
		rebuild => 0,
	},
	cgi => {
		type => "internal",
		default => 0,
		description => "run as a cgi",
		safe => 0,
		rebuild => 0,
	},
	cgi_disable_uploads => {
		type => "internal",
		default => 1,
		description => "whether CGI should accept file uploads",
		safe => 0,
		rebuild => 0,
	},
	post_commit => {
		type => "internal",
		default => 0,
		description => "run as a post-commit hook",
		safe => 0,
		rebuild => 0,
	},
	rebuild => {
		type => "internal",
		default => 0,
		description => "running in rebuild mode",
		safe => 0,
		rebuild => 0,
	},
	setup => {
		type => "internal",
		default => undef,
		description => "running in setup mode",
		safe => 0,
		rebuild => 0,
	},
	refresh => {
		type => "internal",
		default => 0,
		description => "running in refresh mode",
		safe => 0,
		rebuild => 0,
	},
	getctime => {
		type => "internal",
		default => 0,
		description => "running in getctime mode",
		safe => 0,
		rebuild => 0,
	},
	w3mmode => {
		type => "internal",
		default => 0,
		description => "running in w3mmode",
		safe => 0,
		rebuild => 0,
	},
	setupfile => {
		type => "internal",
		default => undef,
		description => "path to setup file",
		safe => 0,
		rebuild => 0,
	},
	allow_symlinks_before_srcdir => {
		type => "string",
		default => 0,
		description => "allow symlinks in the path leading to the srcdir (potentially insecure)",
		safe => 0,
		rebuild => 0,
	},
} #}}}

sub defaultconfig () { #{{{
	my %s=getsetup();
	my @ret;
	foreach my $key (keys %s) {
		push @ret, $key, $s{$key}->{default};
	}
	use Data::Dumper;
	return @ret;
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
		
	if (! defined $config{wiki_file_regexp}) {
		$config{wiki_file_regexp}=qr/(^[$config{wiki_file_chars}]+$)/;
	}

	if (ref $config{ENV} eq 'HASH') {
		foreach my $val (keys %{$config{ENV}}) {
			$ENV{$val}=$config{ENV}{$val};
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

	if (defined $config{umask}) {
		umask(possibly_foolish_untaint($config{umask}));
	}

	run_hooks(checkconfig => sub { shift->() });

	return 1;
} #}}}

sub listplugins () { #{{{
	my %ret;

	foreach my $dir (@INC, $config{libdir}) {
		next unless defined $dir && length $dir;
		foreach my $file (glob("$dir/IkiWiki/Plugin/*.pm")) {
			my ($plugin)=$file=~/.*\/(.*)\.pm$/;
			$ret{$plugin}=1;
		}
	}
	foreach my $dir ($config{libdir}, "$installdir/lib/ikiwiki") {
		next unless defined $dir && length $dir;
		foreach my $file (glob("$dir/plugins/*")) {
			$ret{basename($file)}=1 if -x $file;
		}
	}

	return keys %ret;
} #}}}

sub loadplugins () { #{{{
	if (defined $config{libdir} && length $config{libdir}) {
		unshift @INC, possibly_foolish_untaint($config{libdir});
	}

	foreach my $plugin (@{$config{default_plugins}}, @{$config{add_plugins}}) {
		loadplugin($plugin);
	}
	
	if ($config{rcs}) {
		if (exists $IkiWiki::hooks{rcs}) {
			error(gettext("cannot use multiple rcs plugins"));
		}
		loadplugin($config{rcs});
	}
	if (! exists $IkiWiki::hooks{rcs}) {
		loadplugin("norcs");
	}

	run_hooks(getopt => sub { shift->() });
	if (grep /^-/, @ARGV) {
		print STDERR "Unknown option: $_\n"
			foreach grep /^-/, @ARGV;
		usage();
	}

	return 1;
} #}}}

sub loadplugin ($) { #{{{
	my $plugin=shift;

	return if grep { $_ eq $plugin} @{$config{disable_plugins}};

	foreach my $dir (defined $config{libdir} ? possibly_foolish_untaint($config{libdir}) : undef,
	                 "$installdir/lib/ikiwiki") {
		if (defined $dir && -x "$dir/plugins/$plugin") {
			eval { require IkiWiki::Plugin::external };
			if ($@) {
				my $reason=$@;
				error(sprintf(gettext("failed to load external plugin needed for %s plugin: %s"), $plugin, $reason));
			}
			import IkiWiki::Plugin::external "$dir/plugins/$plugin";
			$loaded_plugins{$plugin}=1;
			return 1;
		}
	}

	my $mod="IkiWiki::Plugin::".possibly_foolish_untaint($plugin);
	eval qq{use $mod};
	if ($@) {
		error("Failed to load plugin $mod: $@");
	}
	$loaded_plugins{$plugin}=1;
	return 1;
} #}}}

sub error ($;$) { #{{{
	my $message=shift;
	my $cleaner=shift;
	log_message('err' => $message) if $config{syslog};
	if (defined $cleaner) {
		$cleaner->();
	}
	die $message."\n";
} #}}}

sub debug ($) { #{{{
	return unless $config{verbose};
	return log_message(debug => @_);
} #}}}

my $log_open=0;
sub log_message ($$) { #{{{
	my $type=shift;

	if ($config{syslog}) {
		require Sys::Syslog;
		if (! $log_open) {
			Sys::Syslog::setlogsock('unix');
			Sys::Syslog::openlog('ikiwiki', '', 'user');
			$log_open=1;
		}
		return eval {
			Sys::Syslog::syslog($type, "[$config{wikiname}] %s", join(" ", @_));
		};
	}
	elsif (! $config{cgi}) {
		return print "@_\n";
	}
	else {
		return print STDERR "@_\n";
	}
} #}}}

sub possibly_foolish_untaint ($) { #{{{
	my $tainted=shift;
	my ($untainted)=$tainted=~/(.*)/s;
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
	return;
} #}}}

sub isinternal ($) { #{{{
	my $page=shift;
	return exists $pagesources{$page} &&
		$pagesources{$page} =~ /\._([^.]+)$/;
} #}}}

sub pagename ($) { #{{{
	my $file=shift;

	my $type=pagetype($file);
	my $page=$file;
	$page=~s/\Q.$type\E*$// if defined $type && !$hooks{htmlize}{$type}{keepextension};
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
	
	return targetpage($page, $config{htmlext});
} #}}}

sub srcfile_stat { #{{{
	my $file=shift;
	my $nothrow=shift;

	return "$config{srcdir}/$file", stat(_) if -e "$config{srcdir}/$file";
	foreach my $dir (@{$config{underlaydirs}}, $config{underlaydir}) {
		return "$dir/$file", stat(_) if -e "$dir/$file";
	}
	error("internal error: $file cannot be found in $config{srcdir} or underlay") unless $nothrow;
	return;
} #}}}

sub srcfile ($;$) { #{{{
	return (srcfile_stat(@_))[0];
} #}}}

sub add_underlay ($) { #{{{
	my $dir=shift;

	if ($dir=~/^\//) {
		unshift @{$config{underlaydirs}}, $dir;
	}
	else {
		unshift @{$config{underlaydirs}}, "$config{underlaydir}/../$dir";
	}

	return 1;
} #}}}

sub readfile ($;$$) { #{{{
	my $file=shift;
	my $binary=shift;
	my $wantfd=shift;

	if (-l $file) {
		error("cannot read a symlink ($file)");
	}
	
	local $/=undef;
	open (my $in, "<", $file) || error("failed to read $file: $!");
	binmode($in) if ($binary);
	return \*$in if $wantfd;
	my $ret=<$in>;
	close $in || error("failed to read $file: $!");
	return $ret;
} #}}}

sub prep_writefile ($$) { #{{{
	my $file=shift;
	my $destdir=shift;
	
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

	return 1;
} #}}}

sub writefile ($$$;$$) { #{{{
	my $file=shift; # can include subdirs
	my $destdir=shift; # directory to put file in
	my $content=shift;
	my $binary=shift;
	my $writer=shift;
	
	prep_writefile($file, $destdir);
	
	my $newfile="$destdir/$file.ikiwiki-new";
	if (-l $newfile) {
		error("cannot write to a symlink ($newfile)");
	}
	
	my $cleanup = sub { unlink($newfile) };
	open (my $out, '>', $newfile) || error("failed to write $newfile: $!", $cleanup);
	binmode($out) if ($binary);
	if ($writer) {
		$writer->(\*$out, $cleanup);
	}
	else {
		print $out $content or error("failed writing to $newfile: $!", $cleanup);
	}
	close $out || error("failed saving $newfile: $!", $cleanup);
	rename($newfile, "$destdir/$file") || 
		error("failed renaming $newfile to $destdir/$file: $!", $cleanup);

	return 1;
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

	return 1;
} #}}}

sub bestlink ($$) { #{{{
	my $page=shift;
	my $link=shift;
	
	my $cwd=$page;
	if ($link=~s/^\/+//) {
		# absolute links
		$cwd="";
	}
	$link=~s/\/$//;

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
	} while $cwd=~s{/?[^/]+$}{};

	if (length $config{userdir}) {
		my $l = "$config{userdir}/".lc($link);
		if (exists $links{$l}) {
			return $l;
		}
		elsif (exists $pagecase{lc $l}) {
			return $pagecase{lc $l};
		}
	}

	#print STDERR "warning: page $page, broken link: $link\n";
	return "";
} #}}}

sub isinlinableimage ($) { #{{{
	my $file=shift;
	
	return $file =~ /\.(png|gif|jpg|jpeg)$/i;
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
	# support use w/o %config set
	my $chars = defined $config{wiki_file_chars} ? $config{wiki_file_chars} : "-[:alnum:]+/.:_";
	$title=~s/([^$chars]|_)/$1 eq ' ' ? '_' : "__".ord($1)."__"/eg;
	return $title;
} #}}}

sub linkpage ($) { #{{{
	my $link=shift;
	my $chars = defined $config{wiki_file_chars} ? $config{wiki_file_chars} : "-[:alnum:]+/.:_";
	$link=~s/([^$chars])/$1 eq ' ' ? '_' : "__".ord($1)."__"/eg;
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

sub displaytime ($;$) { #{{{
	my $time=shift;
	my $format=shift;
	if (! defined $format) {
		$format=$config{timeformat};
	}

	# strftime doesn't know about encodings, so make sure
	# its output is properly treated as utf8
	return decode_utf8(POSIX::strftime($format, localtime($time)));
} #}}}

sub beautify_urlpath ($) { #{{{
	my $url=shift;

	if ($config{usedirs}) {
		$url =~ s!/index.$config{htmlext}$!/!;
	}

	# Ensure url is not an empty link, and
	# if it's relative, make that explicit to avoid colon confusion.
	if ($url !~ /^\//) {
		$url="./$url";
	}

	return $url;
} #}}}

sub urlto ($$;$) { #{{{
	my $to=shift;
	my $from=shift;
	my $absolute=shift;
	
	if (! length $to) {
		return beautify_urlpath(baseurl($from)."index.$config{htmlext}");
	}

	if (! $destsources{$to}) {
		$to=htmlpage($to);
	}

	if ($absolute) {
		return $config{url}.beautify_urlpath("/".$to);
	}

	my $link = abs2rel($to, dirname(htmlpage($from)));

	return beautify_urlpath($link);
} #}}}

sub htmllink ($$$;@) { #{{{
	my $lpage=shift; # the page doing the linking
	my $page=shift; # the page that will contain the link (different for inline)
	my $link=shift;
	my %opts=@_;

	$link=~s/\/$//;

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
		if length $bestlink && $page eq $bestlink &&
		   ! defined $opts{anchor};
	
	if (! $destsources{$bestlink}) {
		$bestlink=htmlpage($bestlink);

		if (! $destsources{$bestlink}) {
			return $linktext unless length $config{cgiurl};
			return "<span class=\"createlink\"><a href=\"".
				cgiurl(
					do => "create",
					page => lc($link),
					from => $lpage
				).
				"\" rel=\"nofollow\">?</a>$linktext</span>"
		}
	}
	
	$bestlink=abs2rel($bestlink, dirname(htmlpage($page)));
	$bestlink=beautify_urlpath($bestlink);
	
	if (! $opts{noimageinline} && isinlinableimage($bestlink)) {
		return "<img src=\"$bestlink\" alt=\"$linktext\" />";
	}

	if (defined $opts{anchor}) {
		$bestlink.="#".$opts{anchor};
	}

	my @attrs;
	if (defined $opts{rel}) {
		push @attrs, ' rel="'.$opts{rel}.'"';
	}
	if (defined $opts{class}) {
		push @attrs, ' class="'.$opts{class}.'"';
	}

	return "<a href=\"$bestlink\"@attrs>$linktext</a>";
} #}}}

sub userlink ($) { #{{{
	my $user=shift;

	my $oiduser=eval { openiduser($user) };
	if (defined $oiduser) {
		return "<a href=\"$user\">$oiduser</a>";
	}
	else {
		eval q{use CGI 'escapeHTML'};
		error($@) if $@;

		return htmllink("", "", escapeHTML(
			length $config{userdir} ? $config{userdir}."/".$user : $user
		), noimageinline => 1);
	}
} #}}}

sub htmlize ($$$$) { #{{{
	my $page=shift;
	my $destpage=shift;
	my $type=shift;
	my $content=shift;
	
	my $oneline = $content !~ /\n/;

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
			destpage => $destpage,
			content => $content,
		);
	});
	
	if ($oneline) {
		# hack to get rid of enclosing junk added by markdown
		# and other htmlizers
		$content=~s/^<p>//i;
		$content=~s/<\/p>$//i;
		chomp $content;
	}

	return $content;
} #}}}

sub linkify ($$$) { #{{{
	my $page=shift;
	my $destpage=shift;
	my $content=shift;

	run_hooks(linkify => sub {
		$content=shift->(
			page => $page,
			destpage => $destpage,
			content => $content,
		);
	});
	
	return $content;
} #}}}

our %preprocessing;
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
		my $prefix=shift;
		my $command=shift;
		my $params=shift;
		$params="" if ! defined $params;

		if (length $escape) {
			return "[[$prefix$command $params]]";
		}
		elsif (exists $hooks{preprocess}{$command}) {
			return "" if $scan && ! $hooks{preprocess}{$command}{scan};
			# Note: preserve order of params, some plugins may
			# consider it significant.
			my @params;
			while ($params =~ m{
				(?:([-\w]+)=)?		# 1: named parameter key?
				(?:
					"""(.*?)"""	# 2: triple-quoted value
				|
					"([^"]+)"	# 3: single-quoted value
				|
					(\S+)		# 4: unquoted value
				)
				(?:\s+|$)		# delimiter to next param
			}sgx) {
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
				return "[[!$command <span class=\"error\">".
					sprintf(gettext("preprocessing loop detected on %s at depth %i"),
						$page, $preprocessing{$page}).
					"</span>]]";
			}
			my $ret;
			if (! $scan) {
				$ret=eval {
					$hooks{preprocess}{$command}{call}->(
						@params,
						page => $page,
						destpage => $destpage,
						preview => $preprocess_preview,
					);
				};
				if ($@) {
					chomp $@;
				 	$ret="[[!$command <span class=\"error\">".
						gettext("Error").": $@"."</span>]]";
				}
			}
			else {
				# use void context during scan pass
				eval {
					$hooks{preprocess}{$command}{call}->(
						@params,
						page => $page,
						destpage => $destpage,
						preview => $preprocess_preview,
					);
				};
				$ret="";
			}
			$preprocessing{$page}--;
			return $ret;
		}
		else {
			return "[[$prefix$command $params]]";
		}
	};
	
	my $regex;
	if ($config{prefix_directives}) {
		$regex = qr{
			(\\?)		# 1: escape?
			\[\[(!)		# directive open; 2: prefix
			([-\w]+)	# 3: command
			(		# 4: the parameters..
				\s+	# Must have space if parameters present
				(?:
					(?:[-\w]+=)?		# named parameter key?
					(?:
						""".*?"""	# triple-quoted value
						|
						"[^"]+"		# single-quoted value
						|
						[^\s\]]+	# unquoted value
					)
					\s*			# whitespace or end
								# of directive
				)
			*)?		# 0 or more parameters
			\]\]		# directive closed
		}sx;
	}
	else {
		$regex = qr{
			(\\?)		# 1: escape?
			\[\[(!?)	# directive open; 2: optional prefix
			([-\w]+)	# 3: command
			\s+
			(		# 4: the parameters..
				(?:
					(?:[-\w]+=)?		# named parameter key?
					(?:
						""".*?"""	# triple-quoted value
						|
						"[^"]+"		# single-quoted value
						|
						[^\s\]]+	# unquoted value
					)
					\s*			# whitespace or end
								# of directive
				)
			*)		# 0 or more parameters
			\]\]		# directive closed
		}sx;
	}

	$content =~ s{$regex}{$handle->($1, $2, $3, $4)}eg;
	return $content;
} #}}}

sub filter ($$$) { #{{{
	my $page=shift;
	my $destpage=shift;
	my $content=shift;

	run_hooks(filter => sub {
		$content=shift->(page => $page, destpage => $destpage, 
			content => $content);
	});

	return $content;
} #}}}

sub indexlink () { #{{{
	return "<a href=\"$config{url}\">$config{wikiname}</a>";
} #}}}

my $wikilock;

sub lockwiki (;$) { #{{{
	my $wait=@_ ? shift : 1;
	# Take an exclusive lock on the wiki to prevent multiple concurrent
	# run issues. The lock will be dropped on program exit.
	if (! -d $config{wikistatedir}) {
		mkdir($config{wikistatedir});
	}
	open($wikilock, '>', "$config{wikistatedir}/lockfile") ||
		error ("cannot write to $config{wikistatedir}/lockfile: $!");
	if (! flock($wikilock, 2 | 4)) { # LOCK_EX | LOCK_NB
		if ($wait) {
			debug("wiki seems to be locked, waiting for lock");
			my $wait=600; # arbitrary, but don't hang forever to 
			              # prevent process pileup
			for (1..$wait) {
				return if flock($wikilock, 2 | 4);
				sleep 1;
			}
			error("wiki is locked; waited $wait seconds without lock being freed (possible stuck process or stale lock?)");
		}
		else {
			return 0;
		}
	}
	return 1;
} #}}}

sub unlockwiki () { #{{{
	return close($wikilock) if $wikilock;
	return;
} #}}}

my $commitlock;

sub commit_hook_enabled () { #{{{
	open($commitlock, '+>', "$config{wikistatedir}/commitlock") ||
		error("cannot write to $config{wikistatedir}/commitlock: $!");
	if (! flock($commitlock, 1 | 4)) { # LOCK_SH | LOCK_NB to test
		close($commitlock) || error("failed closing commitlock: $!");
		return 0;
	}
	close($commitlock) || error("failed closing commitlock: $!");
	return 1;
} #}}}

sub disable_commit_hook () { #{{{
	open($commitlock, '>', "$config{wikistatedir}/commitlock") ||
		error("cannot write to $config{wikistatedir}/commitlock: $!");
	if (! flock($commitlock, 2)) { # LOCK_EX
		error("failed to get commit lock");
	}
	return 1;
} #}}}

sub enable_commit_hook () { #{{{
	return close($commitlock) if $commitlock;
	return;
} #}}}

sub loadindex () { #{{{
	%oldrenderedfiles=%pagectime=();
	if (! $config{rebuild}) {
		%pagesources=%pagemtime=%oldlinks=%links=%depends=
		%destsources=%renderedfiles=%pagecase=%pagestate=();
	}
	my $in;
	if (! open ($in, "<", "$config{wikistatedir}/indexdb")) {
		if (-e "$config{wikistatedir}/index") {
			system("ikiwiki-transition", "indexdb", $config{srcdir});
			open ($in, "<", "$config{wikistatedir}/indexdb") || return;
		}
		else {
			return;
		}
	}
	my $ret=Storable::fd_retrieve($in);
	if (! defined $ret) {
		return 0;
	}
	my %index=%$ret;
	foreach my $src (keys %index) {
		my %d=%{$index{$src}};
		my $page=pagename($src);
		$pagectime{$page}=$d{ctime};
		if (! $config{rebuild}) {
			$pagesources{$page}=$src;
			$pagemtime{$page}=$d{mtime};
			$renderedfiles{$page}=$d{dest};
			if (exists $d{links} && ref $d{links}) {
				$links{$page}=$d{links};
				$oldlinks{$page}=[@{$d{links}}];
			}
			if (exists $d{depends}) {
				$depends{$page}=$d{depends};
			}
			if (exists $d{state}) {
				$pagestate{$page}=$d{state};
			}
		}
		$oldrenderedfiles{$page}=[@{$d{dest}}];
	}
	foreach my $page (keys %pagesources) {
		$pagecase{lc $page}=$page;
	}
	foreach my $page (keys %renderedfiles) {
		$destsources{$_}=$page foreach @{$renderedfiles{$page}};
	}
	return close($in);
} #}}}

sub saveindex () { #{{{
	run_hooks(savestate => sub { shift->() });

	my %hookids;
	foreach my $type (keys %hooks) {
		$hookids{$_}=1 foreach keys %{$hooks{$type}};
	}
	my @hookids=keys %hookids;

	if (! -d $config{wikistatedir}) {
		mkdir($config{wikistatedir});
	}
	my $newfile="$config{wikistatedir}/indexdb.new";
	my $cleanup = sub { unlink($newfile) };
	open (my $out, '>', $newfile) || error("cannot write to $newfile: $!", $cleanup);
	my %index;
	foreach my $page (keys %pagemtime) {
		next unless $pagemtime{$page};
		my $src=$pagesources{$page};

		$index{$src}={
			ctime => $pagectime{$page},
			mtime => $pagemtime{$page},
			dest => $renderedfiles{$page},
			links => $links{$page},
		};

		if (exists $depends{$page}) {
			$index{$src}{depends} = $depends{$page};
		}

		if (exists $pagestate{$page}) {
			foreach my $id (@hookids) {
				foreach my $key (keys %{$pagestate{$page}{$id}}) {
					$index{$src}{state}{$id}{$key}=$pagestate{$page}{$id}{$key};
				}
			}
		}
	}
	my $ret=Storable::nstore_fd(\%index, $out);
	return if ! defined $ret || ! $ret;
	close $out || error("failed saving to $newfile: $!", $cleanup);
	rename($newfile, "$config{wikistatedir}/indexdb") ||
		error("failed renaming $newfile to $config{wikistatedir}/indexdb", $cleanup);
	
	return 1;
} #}}}

sub template_file ($) { #{{{
	my $template=shift;

	foreach my $dir ($config{templatedir}, "$installdir/share/ikiwiki/templates") {
		return "$dir/$template" if -e "$dir/$template";
	}
	return;
} #}}}

sub template_params (@) { #{{{
	my $filename=template_file(shift);

	if (! defined $filename) {
		return if wantarray;
		return "";
	}

	my @ret=(
		filter => sub {
			my $text_ref = shift;
			${$text_ref} = decode_utf8(${$text_ref});
		},
		filename => $filename,
		loop_context_vars => 1,
		die_on_bad_params => 0,
		@_
	);
	return wantarray ? @ret : {@ret};
} #}}}

sub template ($;@) { #{{{
	require HTML::Template;
	return HTML::Template->new(template_params(@_));
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
		error 'hook requires type, call, and id parameters';
	}

	return if $param{no_override} && exists $hooks{$param{type}}{$param{id}};
	
	$hooks{$param{type}}{$param{id}}=\%param;
	return 1;
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

	return 1;
} #}}}

sub rcs_update () { #{{{
	$hooks{rcs}{rcs_update}{call}->(@_);
} #}}}

sub rcs_prepedit ($) { #{{{
	$hooks{rcs}{rcs_prepedit}{call}->(@_);
} #}}}

sub rcs_commit ($$$;$$) { #{{{
	$hooks{rcs}{rcs_commit}{call}->(@_);
} #}}}

sub rcs_commit_staged ($$$) { #{{{
	$hooks{rcs}{rcs_commit_staged}{call}->(@_);
} #}}}

sub rcs_add ($) { #{{{
	$hooks{rcs}{rcs_add}{call}->(@_);
} #}}}

sub rcs_remove ($) { #{{{
	$hooks{rcs}{rcs_remove}{call}->(@_);
} #}}}

sub rcs_rename ($$) { #{{{
	$hooks{rcs}{rcs_rename}{call}->(@_);
} #}}}

sub rcs_recentchanges ($) { #{{{
	$hooks{rcs}{rcs_recentchanges}{call}->(@_);
} #}}}

sub rcs_diff ($) { #{{{
	$hooks{rcs}{rcs_diff}{call}->(@_);
} #}}}

sub rcs_getctime ($) { #{{{
	$hooks{rcs}{rcs_getctime}{call}->(@_);
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

	my $spec=join(' or ', @spec);
	if (@skip) {
		my $skip=join(' and ', @skip);
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
	return ( $s =~ /[^\s]+\s+([^\s]+)/ && $1 ne "and" && $1 ne "or" );
} #}}}

sub safequote ($) { #{{{
	my $s=shift;
	$s=~s/[{}]//g;
	return "q{$s}";
} #}}}

sub add_depends ($$) { #{{{
	my $page=shift;
	my $pagespec=shift;
	
	return unless pagespec_valid($pagespec);

	if (! exists $depends{$page}) {
		$depends{$page}=$pagespec;
	}
	else {
		$depends{$page}=pagespec_merge($depends{$page}, $pagespec);
	}

	return 1;
} # }}}

sub file_pruned ($$) { #{{{
	require File::Spec;
	my $file=File::Spec->canonpath(shift);
	my $base=File::Spec->canonpath(shift);
	$file =~ s#^\Q$base\E/+##;

	my $regexp='('.join('|', @{$config{wiki_file_prune_regexps}}).')';
	return $file =~ m/$regexp/ && $file ne $base;
} #}}}

sub gettext { #{{{
	# Only use gettext in the rare cases it's needed.
	if ((exists $ENV{LANG} && length $ENV{LANG}) ||
	    (exists $ENV{LC_ALL} && length $ENV{LC_ALL}) ||
	    (exists $ENV{LC_MESSAGES} && length $ENV{LC_MESSAGES})) {
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

sub yesno ($) { #{{{
	my $val=shift;

	return (defined $val && lc($val) eq gettext("yes"));
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
	my $spec=shift;

	# Support for old-style GlobLists.
	if (is_globlist($spec)) {
		$spec=globlist_to_pagespec($spec);
	}

	# Convert spec to perl code.
	my $code="";
	while ($spec=~m{
		\s*		# ignore whitespace
		(		# 1: match a single word
			\!		# !
		|
			\(		# (
		|
			\)		# )
		|
			\w+\([^\)]*\)	# command(params)
		|
			[^\s()]+	# any other text
		)
		\s*		# ignore whitespace
	}igx) {
		my $word=$1;
		if (lc $word eq 'and') {
			$code.=' &&';
		}
		elsif (lc $word eq 'or') {
			$code.=' ||';
		}
		elsif ($word eq "(" || $word eq ")" || $word eq "!") {
			$code.=' '.$word;
		}
		elsif ($word =~ /^(\w+)\((.*)\)$/) {
			if (exists $IkiWiki::PageSpec::{"match_$1"}) {
				$code.="IkiWiki::PageSpec::match_$1(\$page, ".safequote($2).", \@_)";
			}
			else {
				$code.=' 0';
			}
		}
		else {
			$code.=" IkiWiki::PageSpec::match_glob(\$page, ".safequote($word).", \@_)";
		}
	}

	if (! length $code) {
		$code=0;
	}

	no warnings;
	return eval 'sub { my $page=shift; '.$code.' }';
} #}}}

sub pagespec_match ($$;@) { #{{{
	my $page=shift;
	my $spec=shift;
	my @params=@_;

	# Backwards compatability with old calling convention.
	if (@params == 1) {
		unshift @params, 'location';
	}

	my $sub=pagespec_translate($spec);
	return IkiWiki::FailReason->new("syntax error in pagespec \"$spec\"") if $@;
	return $sub->($page, @params);
} #}}}

sub pagespec_valid ($) { #{{{
	my $spec=shift;

	my $sub=pagespec_translate($spec);
	return ! $@;
} #}}}
	
sub glob2re ($) { #{{{
	my $re=quotemeta(shift);
	$re=~s/\\\*/.*/g;
	$re=~s/\\\?/./g;
	return $re;
} #}}}

package IkiWiki::FailReason;

use overload ( #{{{
	'""'	=> sub { ${$_[0]} },
	'0+'	=> sub { 0 },
	'!'	=> sub { bless $_[0], 'IkiWiki::SuccessReason'},
	fallback => 1,
); #}}}

sub new { #{{{
	my $class = shift;
	my $value = shift;
	return bless \$value, $class;
} #}}}

package IkiWiki::SuccessReason;

use overload ( #{{{
	'""'	=> sub { ${$_[0]} },
	'0+'	=> sub { 1 },
	'!'	=> sub { bless $_[0], 'IkiWiki::FailReason'},
	fallback => 1,
); #}}}

sub new { #{{{
	my $class = shift;
	my $value = shift;
	return bless \$value, $class;
}; #}}}

package IkiWiki::PageSpec;

sub match_glob ($$;@) { #{{{
	my $page=shift;
	my $glob=shift;
	my %params=@_;
	
	my $from=exists $params{location} ? $params{location} : '';
	
	# relative matching
	if ($glob =~ m!^\./!) {
		$from=~s#/?[^/]+$##;
		$glob=~s#^\./##;
		$glob="$from/$glob" if length $from;
	}

	my $regexp=IkiWiki::glob2re($glob);
	if ($page=~/^$regexp$/i) {
		if (! IkiWiki::isinternal($page) || $params{internal}) {
			return IkiWiki::SuccessReason->new("$glob matches $page");
		}
		else {
			return IkiWiki::FailReason->new("$glob matches $page, but the page is an internal page");
		}
	}
	else {
		return IkiWiki::FailReason->new("$glob does not match $page");
	}
} #}}}

sub match_internal ($$;@) { #{{{
	return match_glob($_[0], $_[1], @_, internal => 1)
} #}}}

sub match_link ($$;@) { #{{{
	my $page=shift;
	my $link=lc(shift);
	my %params=@_;

	my $from=exists $params{location} ? $params{location} : '';

	# relative matching
	if ($link =~ m!^\.! && defined $from) {
		$from=~s#/?[^/]+$##;
		$link=~s#^\./##;
		$link="$from/$link" if length $from;
	}

	my $links = $IkiWiki::links{$page};
	return IkiWiki::FailReason->new("$page has no links") unless $links && @{$links};
	my $bestlink = IkiWiki::bestlink($from, $link);
	foreach my $p (@{$links}) {
		if (length $bestlink) {
			return IkiWiki::SuccessReason->new("$page links to $link")
				if $bestlink eq IkiWiki::bestlink($page, $p);
		}
		else {
			return IkiWiki::SuccessReason->new("$page links to page $p matching $link")
				if match_glob($p, $link, %params);
		}
	}
	return IkiWiki::FailReason->new("$page does not link to $link");
} #}}}

sub match_backlink ($$;@) { #{{{
	return match_link($_[1], $_[0], @_);
} #}}}

sub match_created_before ($$;@) { #{{{
	my $page=shift;
	my $testpage=shift;

	if (exists $IkiWiki::pagectime{$testpage}) {
		if ($IkiWiki::pagectime{$page} < $IkiWiki::pagectime{$testpage}) {
			return IkiWiki::SuccessReason->new("$page created before $testpage");
		}
		else {
			return IkiWiki::FailReason->new("$page not created before $testpage");
		}
	}
	else {
		return IkiWiki::FailReason->new("$testpage has no ctime");
	}
} #}}}

sub match_created_after ($$;@) { #{{{
	my $page=shift;
	my $testpage=shift;

	if (exists $IkiWiki::pagectime{$testpage}) {
		if ($IkiWiki::pagectime{$page} > $IkiWiki::pagectime{$testpage}) {
			return IkiWiki::SuccessReason->new("$page created after $testpage");
		}
		else {
			return IkiWiki::FailReason->new("$page not created after $testpage");
		}
	}
	else {
		return IkiWiki::FailReason->new("$testpage has no ctime");
	}
} #}}}

sub match_creation_day ($$;@) { #{{{
	if ((gmtime($IkiWiki::pagectime{shift()}))[3] == shift) {
		return IkiWiki::SuccessReason->new('creation_day matched');
	}
	else {
		return IkiWiki::FailReason->new('creation_day did not match');
	}
} #}}}

sub match_creation_month ($$;@) { #{{{
	if ((gmtime($IkiWiki::pagectime{shift()}))[4] + 1 == shift) {
		return IkiWiki::SuccessReason->new('creation_month matched');
	}
	else {
		return IkiWiki::FailReason->new('creation_month did not match');
	}
} #}}}

sub match_creation_year ($$;@) { #{{{
	if ((gmtime($IkiWiki::pagectime{shift()}))[5] + 1900 == shift) {
		return IkiWiki::SuccessReason->new('creation_year matched');
	}
	else {
		return IkiWiki::FailReason->new('creation_year did not match');
	}
} #}}}

1
