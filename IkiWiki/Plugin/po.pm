#!/usr/bin/perl
# .po as a wiki page type
# Licensed under GPL v2 or greater
# Copyright (C) 2008 intrigeri <intrigeri@boum.org>
# inspired by the GPL'd po4a-translate,
# which is Copyright 2002, 2003, 2004 by Martin Quinson (mquinson#debian.org)
package IkiWiki::Plugin::po;

use warnings;
use strict;
use IkiWiki 2.00;
use Encode;
use Locale::Po4a::Chooser;
use Locale::Po4a::Po;
use File::Basename;
use File::Copy;
use File::Spec;
use File::Temp;
use Memoize;
use UNIVERSAL;

my %translations;
my @origneedsbuild;
my %origsubs;

memoize("istranslatable");
memoize("_istranslation");
memoize("percenttranslated");

sub import {
	hook(type => "getsetup", id => "po", call => \&getsetup);
	hook(type => "checkconfig", id => "po", call => \&checkconfig);
	hook(type => "needsbuild", id => "po", call => \&needsbuild);
	hook(type => "scan", id => "po", call => \&scan, last =>1);
	hook(type => "filter", id => "po", call => \&filter);
	hook(type => "htmlize", id => "po", call => \&htmlize);
	hook(type => "pagetemplate", id => "po", call => \&pagetemplate, last => 1);
	hook(type => "postscan", id => "po", call => \&postscan);
	hook(type => "rename", id => "po", call => \&renamepages, first => 1);
	hook(type => "delete", id => "po", call => \&mydelete);
	hook(type => "change", id => "po", call => \&change);
	hook(type => "canremove", id => "po", call => \&canremove);
	hook(type => "canrename", id => "po", call => \&canrename);
	hook(type => "editcontent", id => "po", call => \&editcontent);

	$origsubs{'bestlink'}=\&IkiWiki::bestlink;
	inject(name => "IkiWiki::bestlink", call => \&mybestlink);
	$origsubs{'beautify_urlpath'}=\&IkiWiki::beautify_urlpath;
	inject(name => "IkiWiki::beautify_urlpath", call => \&mybeautify_urlpath);
	$origsubs{'targetpage'}=\&IkiWiki::targetpage;
	inject(name => "IkiWiki::targetpage", call => \&mytargetpage);
	$origsubs{'urlto'}=\&IkiWiki::urlto;
	inject(name => "IkiWiki::urlto", call => \&myurlto);
	$origsubs{'nicepagetitle'}=\&IkiWiki::nicepagetitle;
	inject(name => "IkiWiki::nicepagetitle", call => \&mynicepagetitle);
}


# ,----
# | Table of contents
# `----

# 1. Hooks
# 2. Injected functions
# 3. Blackboxes for private data
# 4. Helper functions
# 5. PageSpec's


# ,----
# | Hooks
# `----

sub getsetup () {
	return
		plugin => {
			safe => 0,
			rebuild => 1,
		},
		po_master_language => {
			type => "string",
			example => {
				'code' => 'en',
				'name' => 'English'
			},
			description => "master language (non-PO files)",
			safe => 1,
			rebuild => 1,
		},
		po_slave_languages => {
			type => "string",
			example => {
				'fr' => 'Français',
				'es' => 'Castellano',
				'de' => 'Deutsch'
			},
			description => "slave languages (PO files)",
			safe => 1,
			rebuild => 1,
		},
		po_translatable_pages => {
			type => "pagespec",
			example => "!*/Discussion",
			description => "PageSpec controlling which pages are translatable",
			link => "ikiwiki/PageSpec",
			safe => 1,
			rebuild => 1,
		},
		po_link_to => {
			type => "string",
			example => "current",
			description => "internal linking behavior (default/current/negotiated)",
			safe => 1,
			rebuild => 1,
		},
		po_translation_status_in_links => {
			type => "boolean",
			example => 1,
			description => "display translation status in links to translations",
			safe => 1,
			rebuild => 1,
		},
}

sub checkconfig () {
	foreach my $field (qw{po_master_language po_slave_languages}) {
		if (! exists $config{$field} || ! defined $config{$field}) {
			error(sprintf(gettext("Must specify %s"), $field));
		}
	}
	if (! (keys %{$config{po_slave_languages}})) {
		error(gettext("At least one slave language must be defined in po_slave_languages"));
	}
	map {
		islanguagecode($_)
			or error(sprintf(gettext("%s is not a valid language code"), $_));
	} ($config{po_master_language}{code}, keys %{$config{po_slave_languages}});
	if (! exists $config{po_translatable_pages} ||
	    ! defined $config{po_translatable_pages}) {
		$config{po_translatable_pages}="";
	}
	if (! exists $config{po_link_to} ||
	    ! defined $config{po_link_to}) {
		$config{po_link_to}='default';
	}
	elsif (! grep {
			$config{po_link_to} eq $_
		} ('default', 'current', 'negotiated')) {
		warn(sprintf(gettext('po_link_to=%s is not a valid setting, falling back to po_link_to=default'),
				$config{po_link_to}));
		$config{po_link_to}='default';
	}
	elsif ($config{po_link_to} eq "negotiated" && ! $config{usedirs}) {
		warn(gettext('po_link_to=negotiated requires usedirs to be enabled, falling back to po_link_to=default'));
		$config{po_link_to}='default';
	}
	if (! exists $config{po_translation_status_in_links} ||
	    ! defined $config{po_translation_status_in_links}) {
		$config{po_translation_status_in_links}=1;
	}
	push @{$config{wiki_file_prune_regexps}}, qr/\.pot$/;
}

sub needsbuild () {
	my $needsbuild=shift;

	# backup @needsbuild content so that change() can know whether
	# a given master page was rendered because its source file was changed
	@origneedsbuild=(@$needsbuild);

	flushmemoizecache();
	buildtranslationscache();

	# make existing translations depend on the corresponding master page
	foreach my $master (keys %translations) {
		map add_depends($_, $master), values %{otherlanguages($master)};
	}
}

# Massage the recorded state of internal links so that:
# - it matches the actually generated links, rather than the links as written
#   in the pages' source
# - backlinks are consistent in all cases
sub scan (@) {
	my %params=@_;
	my $page=$params{page};
	my $content=$params{content};

	return unless UNIVERSAL::can("IkiWiki::Plugin::link", "import");

	if (istranslation($page)) {
		foreach my $destpage (@{$links{$page}}) {
			if (istranslatable($destpage)) {
				# replace one occurence of $destpage in $links{$page}
				# (we only want to replace the one that was added by
				# IkiWiki::Plugin::link::scan, other occurences may be
				# there for other reasons)
				for (my $i=0; $i<@{$links{$page}}; $i++) {
					if (@{$links{$page}}[$i] eq $destpage) {
						@{$links{$page}}[$i] = $destpage . '.' . lang($page);
						last;
					}
				}
			}
		}
	}
	elsif (! istranslatable($page) && ! istranslation($page)) {
		foreach my $destpage (@{$links{$page}}) {
			if (istranslatable($destpage)) {
				# make sure any destpage's translations has
				# $page in its backlinks
				push @{$links{$page}},
					values %{otherlanguages($destpage)};
			}
		}
	}
}

# We use filter to convert PO to the master page's format,
# since the rest of ikiwiki should not work on PO files.
sub filter (@) {
	my %params = @_;

	my $page = $params{page};
	my $destpage = $params{destpage};
	my $content = decode_utf8(encode_utf8($params{content}));

	return $content if ( ! istranslation($page)
			     || alreadyfiltered($page, $destpage) );

	# CRLF line terminators make poor Locale::Po4a feel bad
	$content=~s/\r\n/\n/g;

	# There are incompatibilities between some File::Temp versions
	# (including 0.18, bundled with Lenny's perl-modules package)
	# and others (e.g. 0.20, previously present in the archive as
	# a standalone package): under certain circumstances, some
	# return a relative filename, whereas others return an absolute one;
	# we here use this module in a way that is at least compatible
	# with 0.18 and 0.20. Beware, hit'n'run refactorers!
	my $infile = new File::Temp(TEMPLATE => "ikiwiki-po-filter-in.XXXXXXXXXX",
				    DIR => File::Spec->tmpdir,
				    UNLINK => 1)->filename;
	my $outfile = new File::Temp(TEMPLATE => "ikiwiki-po-filter-out.XXXXXXXXXX",
				     DIR => File::Spec->tmpdir,
				     UNLINK => 1)->filename;

	writefile(basename($infile), File::Spec->tmpdir, $content);

	my $masterfile = srcfile($pagesources{masterpage($page)});
	my %options = (
		"markdown" => (pagetype($masterfile) eq 'mdwn') ? 1 : 0,
	);
	my $doc=Locale::Po4a::Chooser::new('text',%options);
	$doc->process(
		'po_in_name'	=> [ $infile ],
		'file_in_name'	=> [ $masterfile ],
		'file_in_charset'  => 'utf-8',
		'file_out_charset' => 'utf-8',
	) or error("[po/filter:$page]: failed to translate");
	$doc->write($outfile) or error("[po/filter:$page] could not write $outfile");
	$content = readfile($outfile) or error("[po/filter:$page] could not read $outfile");

	# Unlinking should happen automatically, thanks to File::Temp,
	# but it does not work here, probably because of the way writefile()
	# and Locale::Po4a::write() work.
	unlink $infile, $outfile;

	setalreadyfiltered($page, $destpage);
	return $content;
}

sub htmlize (@) {
	my %params=@_;

	my $page = $params{page};
	my $content = $params{content};

	# ignore PO files this plugin did not create
	return $content unless istranslation($page);

	# force content to be htmlize'd as if it was the same type as the master page
	return IkiWiki::htmlize($page, $page,
				pagetype(srcfile($pagesources{masterpage($page)})),
				$content);
}

sub pagetemplate (@) {
	my %params=@_;
	my $page=$params{page};
	my $destpage=$params{destpage};
	my $template=$params{template};

	my ($masterpage, $lang) = istranslation($page);

	if (istranslation($page) && $template->query(name => "percenttranslated")) {
		$template->param(percenttranslated => percenttranslated($page));
	}
	if ($template->query(name => "istranslation")) {
		$template->param(istranslation => scalar istranslation($page));
	}
	if ($template->query(name => "istranslatable")) {
		$template->param(istranslatable => istranslatable($page));
	}
	if ($template->query(name => "HOMEPAGEURL")) {
		$template->param(homepageurl => homepageurl($page));
	}
	if ($template->query(name => "otherlanguages")) {
		$template->param(otherlanguages => [otherlanguagesloop($page)]);
		map add_depends($page, $_), (values %{otherlanguages($page)});
	}
	# Rely on IkiWiki::Render's genpage() to decide wether
	# a discussion link should appear on $page; this is not
	# totally accurate, though: some broken links may be generated
	# when cgiurl is disabled.
	# This compromise avoids some code duplication, and will probably
	# prevent future breakage when ikiwiki internals change.
	# Known limitations are preferred to future random bugs.
	if ($template->param('discussionlink') && istranslation($page)) {
		$template->param('discussionlink' => htmllink(
							$page,
							$destpage,
							$masterpage . '/' . gettext("Discussion"),
							noimageinline => 1,
							forcesubpage => 0,
							linktext => gettext("Discussion"),
							));
	}
	# Remove broken parentlink to ./index.html on home page's translations.
	# It works because this hook has the "last" parameter set, to ensure it
	# runs after parentlinks' own pagetemplate hook.
	if ($template->param('parentlinks')
	    && istranslation($page)
	    && $masterpage eq "index") {
		$template->param('parentlinks' => []);
	}
} # }}}

sub postscan (@) {
	my %params = @_;
	my $page = $params{page};

	# backlinks involve back-dependencies, so that nicepagetitle effects,
	# such as translation status displayed in links, are updated
	use IkiWiki::Render;
	map add_depends($page, $_), keys %{$IkiWiki::backlinks{$page}};
}

# Add the renamed page translations to the list of to-be-renamed pages.
sub renamepages($$$) {
	my ($torename, $cgi, $session) = (shift, shift, shift);

	# copy the initial array, so that we can iterate on it AND
	# modify it at the same time, without iterating on the items we
	# pushed on it ourselves
	my @torename=@{$torename};

	# Save the page(s) the user asked to rename, so that our
	# canrename hook can tell the difference between:
	#  - a translation being renamed as a consequence of its master page
	#    being renamed
	#  - a user trying to directly rename a translation
	# This is why this hook has to be run first, before @torename is modified
	# by other plugins.
	$session->param(po_orig_torename => [ @torename ]);
	IkiWiki::cgi_savesession($session);

	foreach my $rename (@torename) {
		next unless istranslatable($rename->{src});
		my %otherpages=%{otherlanguages($rename->{src})};
		while (my ($lang, $otherpage) = each %otherpages) {
			push @{$torename}, {
				src => $otherpage,
				srcfile => $pagesources{$otherpage},
				dest => otherlanguage($rename->{dest}, $lang),
				destfile => $rename->{dest}.".".$lang.".po",
				required => 0,
			};
		}
	}
}

sub mydelete(@) {
	my @deleted=@_;

	map { deletetranslations($_) } grep istranslatablefile($_), @deleted;
}

sub change(@) {
	my @rendered=@_;

	my $updated_po_files=0;

	# Refresh/create POT and PO files as needed.
	foreach my $file (grep {istranslatablefile($_)} @rendered) {
		my $page=pagename($file);
		my $masterfile=srcfile($file);
		my $updated_pot_file=0;
		# Only refresh Pot file if it does not exist, or if
		# $pagesources{$page} was changed: don't if only the HTML was
		# refreshed, e.g. because of a dependency.
		if ((grep { $_ eq $pagesources{$page} } @origneedsbuild)
		    || ! -e potfile($masterfile)) {
			refreshpot($masterfile);
			$updated_pot_file=1;
		}
		my @pofiles;
		map {
			push @pofiles, $_ if ($updated_pot_file || ! -e $_);
		} (pofiles($masterfile));
		if (@pofiles) {
			refreshpofiles($masterfile, @pofiles);
			map { IkiWiki::rcs_add($_) } @pofiles if $config{rcs};
			$updated_po_files=1;
		}
	}

	if ($updated_po_files) {
		commit_and_refresh(
			gettext("updated PO files"),
			"IkiWiki::Plugin::po::change");
	}
}

sub canremove ($$$) {
	my ($page, $cgi, $session) = (shift, shift, shift);

	if (istranslation($page)) {
		return gettext("Can not remove a translation. Removing the master page, ".
			       "though, removes its translations as well.");
	}
	return undef;
}

sub canrename ($$@) {
	my ($cgi, $session) = (shift, shift);
	my %params = @_;

	if (istranslation($params{src})) {
		my $masterpage = masterpage($params{src});
		# Tell the difference between:
		#  - a translation being renamed as a consequence of its master page
		#    being renamed, which is allowed
		#  - a user trying to directly rename a translation, which is forbidden
		# by looking for the master page in the list of to-be-renamed pages we
		# saved early in the renaming process.
		my $orig_torename = $session->param("po_orig_torename");
		unless (scalar grep { $_->{src} eq $masterpage } @{$orig_torename}) {
			return gettext("Can not rename a translation. Renaming the master page, ".
				       "though, renames its translations as well.");
		}
	}
	return undef;
}

# As we're previewing or saving a page, the content may have
# changed, so tell the next filter() invocation it must not be lazy.
sub editcontent () {
	my %params=@_;

	unsetalreadyfiltered($params{page}, $params{page});
	return $params{content};
}


# ,----
# | Injected functions
# `----

# Implement po_link_to 'current' and 'negotiated' settings.
sub mybestlink ($$) {
	my $page=shift;
	my $link=shift;

	my $res=$origsubs{'bestlink'}->(masterpage($page), $link);
	if (length $res
	    && ($config{po_link_to} eq "current" || $config{po_link_to} eq "negotiated")
	    && istranslatable($res)
	    && istranslation($page)) {
		return $res . "." . lang($page);
	}
	return $res;
}

sub mybeautify_urlpath ($) {
	my $url=shift;

	my $res=$origsubs{'beautify_urlpath'}->($url);
	if ($config{po_link_to} eq "negotiated") {
		$res =~ s!/\Qindex.$config{po_master_language}{code}.$config{htmlext}\E$!/!;
		$res =~ s!/\Qindex.$config{htmlext}\E$!/!;
		map {
			$res =~ s!/\Qindex.$_.$config{htmlext}\E$!/!;
		} (keys %{$config{po_slave_languages}});
	}
	return $res;
}

sub mytargetpage ($$) {
	my $page=shift;
	my $ext=shift;

	if (istranslation($page) || istranslatable($page)) {
		my ($masterpage, $lang) = (masterpage($page), lang($page));
		if (! $config{usedirs} || $masterpage eq 'index') {
			return $masterpage . "." . $lang . "." . $ext;
		}
		else {
			return $masterpage . "/index." . $lang . "." . $ext;
		}
	}
	return $origsubs{'targetpage'}->($page, $ext);
}

sub myurlto ($$;$) {
	my $to=shift;
	my $from=shift;
	my $absolute=shift;

	# workaround hard-coded /index.$config{htmlext} in IkiWiki::urlto()
	if (! length $to
	    && $config{po_link_to} eq "current"
	    && istranslatable('index')) {
		return IkiWiki::beautify_urlpath(IkiWiki::baseurl($from) . "index." . lang($from) . ".$config{htmlext}");
	}
	# avoid using our injected beautify_urlpath if run by cgi_editpage,
	# so that one is redirected to the just-edited page rather than to the
	# negociated translation; to prevent unnecessary fiddling with caller/inject,
	# we only do so when our beautify_urlpath would actually do what we want to
	# avoid, i.e. when po_link_to = negotiated
	if ($config{po_link_to} eq "negotiated") {
		my @caller = caller(1);
		my $run_by_editpage = 0;
		$run_by_editpage = 1 if (exists $caller[3] && defined $caller[3]
					 && $caller[3] eq "IkiWiki::cgi_editpage");
		inject(name => "IkiWiki::beautify_urlpath", call => $origsubs{'beautify_urlpath'})
			if $run_by_editpage;
		my $res = $origsubs{'urlto'}->($to,$from,$absolute);
		inject(name => "IkiWiki::beautify_urlpath", call => \&mybeautify_urlpath)
			if $run_by_editpage;
		return $res;
	}
	else {
		return $origsubs{'urlto'}->($to,$from,$absolute)
	}
}

sub mynicepagetitle ($;$) {
	my ($page, $unescaped) = (shift, shift);

	my $res = $origsubs{'nicepagetitle'}->($page, $unescaped);
	return $res unless istranslation($page);
	return $res unless $config{po_translation_status_in_links};
	return $res.' ('.percenttranslated($page).' %)';
}

# ,----
# | Blackboxes for private data
# `----

{
	my %filtered;

	sub alreadyfiltered($$) {
		my $page=shift;
		my $destpage=shift;

		return ( exists $filtered{$page}{$destpage}
			 && $filtered{$page}{$destpage} eq 1 );
	}

	sub setalreadyfiltered($$) {
		my $page=shift;
		my $destpage=shift;

		$filtered{$page}{$destpage}=1;
	}

	sub unsetalreadyfiltered($$) {
		my $page=shift;
		my $destpage=shift;

		if (exists $filtered{$page}{$destpage}) {
			delete $filtered{$page}{$destpage};
		}
	}

	sub resetalreadyfiltered() {
		undef %filtered;
	}
}

# ,----
# | Helper functions
# `----

sub maybe_add_leading_slash ($;$) {
	my $str=shift;
	my $add=shift;
	$add=1 unless defined $add;
	return '/' . $str if $add;
	return $str;
}

sub istranslatablefile ($) {
	my $file=shift;

	return 0 unless defined $file;
	return 0 if (defined pagetype($file) && pagetype($file) eq 'po');
	return 0 if $file =~ /\.pot$/;
	return 1 if pagespec_match(pagename($file), $config{po_translatable_pages});
	return;
}

sub istranslatable ($) {
	my $page=shift;

	$page=~s#^/##;
	return 1 if istranslatablefile($pagesources{$page});
	return;
}

sub _istranslation ($) {
	my $page=shift;

	my $hasleadingslash = ($page=~s#^/##);
	my $file=$pagesources{$page};
	return 0 unless (defined $file
			 && defined pagetype($file)
			 && pagetype($file) eq 'po');
	return 0 if $file =~ /\.pot$/;

	my ($masterpage, $lang) = ($page =~ /(.*)[.]([a-z]{2})$/);
	return 0 unless (defined $masterpage && defined $lang
			 && length $masterpage && length $lang
			 && defined $pagesources{$masterpage}
			 && defined $config{po_slave_languages}{$lang});

	return (maybe_add_leading_slash($masterpage, $hasleadingslash), $lang)
		if istranslatable($masterpage);
}

sub istranslation ($) {
	my $page=shift;

	if (1 < (my ($masterpage, $lang) = _istranslation($page))) {
		my $hasleadingslash = ($masterpage=~s#^/##);
		$translations{$masterpage}{$lang}=$page unless exists $translations{$masterpage}{$lang};
		return (maybe_add_leading_slash($masterpage, $hasleadingslash), $lang);
	}
	return;
}

sub masterpage ($) {
	my $page=shift;

	if ( 1 < (my ($masterpage, $lang) = _istranslation($page))) {
		return $masterpage;
	}
	return $page;
}

sub lang ($) {
	my $page=shift;

	if (1 < (my ($masterpage, $lang) = _istranslation($page))) {
		return $lang;
	}
	return $config{po_master_language}{code};
}

sub islanguagecode ($) {
	my $code=shift;

	return ($code =~ /^[a-z]{2}$/);
}

sub otherlanguage ($$) {
	my $page=shift;
	my $code=shift;

	return masterpage($page) if $code eq $config{po_master_language}{code};
	return masterpage($page) . '.' . $code;
}

sub otherlanguages ($) {
	my $page=shift;

	my %ret;
	return \%ret unless (istranslation($page) || istranslatable($page));
	my $curlang=lang($page);
	foreach my $lang
		($config{po_master_language}{code}, keys %{$config{po_slave_languages}}) {
		next if $lang eq $curlang;
		$ret{$lang}=otherlanguage($page, $lang);
	}
	return \%ret;
}

sub potfile ($) {
	my $masterfile=shift;

	(my $name, my $dir, my $suffix) = fileparse($masterfile, qr/\.[^.]*/);
	$dir='' if $dir eq './';
	return File::Spec->catpath('', $dir, $name . ".pot");
}

sub pofile ($$) {
	my $masterfile=shift;
	my $lang=shift;

	(my $name, my $dir, my $suffix) = fileparse($masterfile, qr/\.[^.]*/);
	$dir='' if $dir eq './';
	return File::Spec->catpath('', $dir, $name . "." . $lang . ".po");
}

sub pofiles ($) {
	my $masterfile=shift;

	return map pofile($masterfile, $_), (keys %{$config{po_slave_languages}});
}

sub refreshpot ($) {
	my $masterfile=shift;

	my $potfile=potfile($masterfile);
	my %options = ("markdown" => (pagetype($masterfile) eq 'mdwn') ? 1 : 0);
	my $doc=Locale::Po4a::Chooser::new('text',%options);
	$doc->{TT}{utf_mode} = 1;
	$doc->{TT}{file_in_charset} = 'utf-8';
	$doc->{TT}{file_out_charset} = 'utf-8';
	$doc->read($masterfile);
	# let's cheat a bit to force porefs option to be passed to Locale::Po4a::Po;
	# this is undocument use of internal Locale::Po4a::TransTractor's data,
	# compulsory since this module prevents us from using the porefs option.
	$doc->{TT}{po_out}=Locale::Po4a::Po->new({ 'porefs' => 'none' });
	$doc->{TT}{po_out}->set_charset('utf-8');
	# do the actual work
	$doc->parse;
	IkiWiki::prep_writefile(basename($potfile),dirname($potfile));
	$doc->writepo($potfile);
}

sub refreshpofiles ($@) {
	my $masterfile=shift;
	my @pofiles=@_;

	my $potfile=potfile($masterfile);
	error("[po/refreshpofiles] POT file ($potfile) does not exist") unless (-e $potfile);

	foreach my $pofile (@pofiles) {
		IkiWiki::prep_writefile(basename($pofile),dirname($pofile));
		if (-e $pofile) {
			system("msgmerge", "-U", "--backup=none", $pofile, $potfile) == 0
				or error("[po/refreshpofiles:$pofile] failed to update");
		}
		else {
			File::Copy::syscopy($potfile,$pofile)
				or error("[po/refreshpofiles:$pofile] failed to copy the POT file");
		}
	}
}

sub buildtranslationscache() {
	# use istranslation's side-effect
	map istranslation($_), (keys %pagesources);
}

sub resettranslationscache() {
	undef %translations;
}

sub flushmemoizecache() {
	Memoize::flush_cache("istranslatable");
	Memoize::flush_cache("_istranslation");
	Memoize::flush_cache("percenttranslated");
}

sub urlto_with_orig_beautiful_urlpath($$) {
	my $to=shift;
	my $from=shift;

	inject(name => "IkiWiki::beautify_urlpath", call => $origsubs{'beautify_urlpath'});
	my $res=urlto($to, $from);
	inject(name => "IkiWiki::beautify_urlpath", call => \&mybeautify_urlpath);

	return $res;
}

sub percenttranslated ($) {
	my $page=shift;

	$page=~s/^\///;
	return gettext("N/A") unless istranslation($page);
	my $file=srcfile($pagesources{$page});
	my $masterfile = srcfile($pagesources{masterpage($page)});
	my %options = (
		"markdown" => (pagetype($masterfile) eq 'mdwn') ? 1 : 0,
	);
	my $doc=Locale::Po4a::Chooser::new('text',%options);
	$doc->process(
		'po_in_name'	=> [ $file ],
		'file_in_name'	=> [ $masterfile ],
		'file_in_charset'  => 'utf-8',
		'file_out_charset' => 'utf-8',
	) or error("[po/percenttranslated:$page]: failed to translate");
	my ($percent,$hit,$queries) = $doc->stats();
	return $percent;
}

sub languagename ($) {
	my $code=shift;

	return $config{po_master_language}{name}
		if $code eq $config{po_master_language}{code};
	return $config{po_slave_languages}{$code}
		if defined $config{po_slave_languages}{$code};
	return;
}

sub otherlanguagesloop ($) {
	my $page=shift;

	my @ret;
	my %otherpages=%{otherlanguages($page)};
	while (my ($lang, $otherpage) = each %otherpages) {
		if (istranslation($page) && masterpage($page) eq $otherpage) {
			push @ret, {
				url => urlto_with_orig_beautiful_urlpath($otherpage, $page),
				code => $lang,
				language => languagename($lang),
				master => 1,
			};
		}
		else {
			push @ret, {
				url => urlto_with_orig_beautiful_urlpath($otherpage, $page),
				code => $lang,
				language => languagename($lang),
				percent => percenttranslated($otherpage),
			}
		}
	}
	return sort {
			return -1 if $a->{code} eq $config{po_master_language}{code};
			return 1 if $b->{code} eq $config{po_master_language}{code};
			return $a->{language} cmp $b->{language};
		} @ret;
}

sub homepageurl (;$) {
	my $page=shift;

	return urlto('', $page);
}

sub deletetranslations ($) {
	my $deletedmasterfile=shift;

	my $deletedmasterpage=pagename($deletedmasterfile);
	my @todelete;
	map {
		my $file = newpagefile($deletedmasterpage.'.'.$_, 'po');
		my $absfile = "$config{srcdir}/$file";
		if (-e $absfile && ! -l $absfile && ! -d $absfile) {
			push @todelete, $file;
		}
	} keys %{$config{po_slave_languages}};

	map {
		if ($config{rcs}) {
			IkiWiki::rcs_remove($_);
		}
		else {
			IkiWiki::prune("$config{srcdir}/$_");
		}
	} @todelete;

	if (scalar @todelete) {
		commit_and_refresh(
			gettext("removed obsolete PO files"),
			"IkiWiki::Plugin::po::deletetranslations");
	}
}

sub commit_and_refresh ($$) {
	my ($msg, $author) = (shift, shift);

	if ($config{rcs}) {
		IkiWiki::disable_commit_hook();
		IkiWiki::rcs_commit_staged($msg, $author, "127.0.0.1");
		IkiWiki::enable_commit_hook();
		IkiWiki::rcs_update();
	}
	# Reinitialize module's private variables.
	resetalreadyfiltered();
	resettranslationscache();
	flushmemoizecache();
	# Trigger a wiki refresh.
	require IkiWiki::Render;
	# without preliminary saveindex/loadindex, refresh()
	# complains about a lot of uninitialized variables
	IkiWiki::saveindex();
	IkiWiki::loadindex();
	IkiWiki::refresh();
	IkiWiki::saveindex();
}

# ,----
# | PageSpec's
# `----

package IkiWiki::PageSpec;
use warnings;
use strict;
use IkiWiki 2.00;

sub match_istranslation ($;@) {
	my $page=shift;

	if (IkiWiki::Plugin::po::istranslation($page)) {
		return IkiWiki::SuccessReason->new("is a translation page");
	}
	else {
		return IkiWiki::FailReason->new("is not a translation page");
	}
}

sub match_istranslatable ($;@) {
	my $page=shift;

	if (IkiWiki::Plugin::po::istranslatable($page)) {
		return IkiWiki::SuccessReason->new("is set as translatable in po_translatable_pages");
	}
	else {
		return IkiWiki::FailReason->new("is not set as translatable in po_translatable_pages");
	}
}

sub match_lang ($$;@) {
	my $page=shift;
	my $wanted=shift;

	my $regexp=IkiWiki::glob2re($wanted);
	my $lang=IkiWiki::Plugin::po::lang($page);
	if ($lang!~/^$regexp$/i) {
		return IkiWiki::FailReason->new("file language is $lang, not $wanted");
	}
	else {
		return IkiWiki::SuccessReason->new("file language is $wanted");
	}
}

sub match_currentlang ($$;@) {
	my $page=shift;
	shift;
	my %params=@_;

	return IkiWiki::FailReason->new("no location provided") unless exists $params{location};

	my $currentlang=IkiWiki::Plugin::po::lang($params{location});
	my $lang=IkiWiki::Plugin::po::lang($page);

	if ($lang eq $currentlang) {
		return IkiWiki::SuccessReason->new("file language is the same as current one, i.e. $currentlang");
	}
	else {
		return IkiWiki::FailReason->new("file language is $lang, whereas current language is $currentlang");
	}
}

1
