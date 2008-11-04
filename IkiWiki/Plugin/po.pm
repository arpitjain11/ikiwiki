#!/usr/bin/perl
# .po as a wiki page type
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

my %translations;
our %filtered;

memoize("_istranslation");
memoize("percenttranslated");
# FIXME: memoizing istranslatable() makes some test cases fail once every
# two tries; this may be related to the artificial way the testsuite is
# run, or not.
# memoize("istranslatable");

# backup references to subs that will be overriden
my %origsubs;
$origsubs{'bestlink'}=\&IkiWiki::bestlink;
$origsubs{'beautify_urlpath'}=\&IkiWiki::beautify_urlpath;
$origsubs{'targetpage'}=\&IkiWiki::targetpage;

sub import {
	hook(type => "getsetup", id => "po", call => \&getsetup);
	hook(type => "checkconfig", id => "po", call => \&checkconfig);
	hook(type => "needsbuild", id => "po", call => \&needsbuild);
	hook(type => "filter", id => "po", call => \&filter);
	hook(type => "htmlize", id => "po", call => \&htmlize);
	hook(type => "pagetemplate", id => "po", call => \&pagetemplate);
	hook(type => "editcontent", id => "po", call => \&editcontent);
	inject(name => "IkiWiki::bestlink", call => \&mybestlink);
	inject(name => "IkiWiki::beautify_urlpath", call => \&mybeautify_urlpath);
	inject(name => "IkiWiki::targetpage", call => \&mytargetpage);
}

sub getsetup () { #{{{
	return
		plugin => {
			safe => 0,
			rebuild => 1, # format plugin
		},
		po_master_language => {
			type => "string",
			example => {
				'code' => 'en',
				'name' => 'English'
			},
			description => "master language (non-PO files)",
			safe => 0,
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
			safe => 0,
			rebuild => 1,
		},
		po_translatable_pages => {
			type => "pagespec",
			example => "!*/Discussion",
			description => "PageSpec controlling which pages are translatable",
			link => "ikiwiki/PageSpec",
			safe => 0,
			rebuild => 1,
		},
		po_link_to => {
			type => "string",
			example => "current",
			description => "internal linking behavior (default/current/negotiated)",
			safe => 0,
			rebuild => 1,
		},
} #}}}

sub checkconfig () { #{{{
	foreach my $field (qw{po_master_language po_slave_languages}) {
		if (! exists $config{$field} || ! defined $config{$field}) {
			error(sprintf(gettext("Must specify %s"), $field));
		}
	}
	if (! exists $config{po_link_to} ||
	    ! defined $config{po_link_to}) {
	    $config{po_link_to}="default";
	}
	if (! exists $config{po_translatable_pages} ||
	    ! defined $config{po_translatable_pages}) {
	    $config{po_translatable_pages}="";
	}
	if ($config{po_link_to} eq "negotiated" && ! $config{usedirs}) {
		error(gettext("po_link_to=negotiated requires usedirs to be set"));
	}
	push @{$config{wiki_file_prune_regexps}}, qr/\.pot$/;
} #}}}

sub potfile ($) { #{{{
	my $masterfile=shift;
	(my $name, my $dir, my $suffix) = fileparse($masterfile, qr/\.[^.]*/);
	return File::Spec->catfile($dir, $name . ".pot");
} #}}}

sub pofile ($$) { #{{{
	my $masterfile=shift;
	my $lang=shift;
	(my $name, my $dir, my $suffix) = fileparse($masterfile, qr/\.[^.]*/);
	return File::Spec->catfile($dir, $name . "." . $lang . ".po");
} #}}}

sub refreshpot ($) { #{{{
	my $masterfile=shift;
	my $potfile=potfile($masterfile);
	my %options = ("markdown" => (pagetype($masterfile) eq 'mdwn') ? 1 : 0);
	my $doc=Locale::Po4a::Chooser::new('text',%options);
	$doc->read($masterfile);
	$doc->{TT}{utf_mode} = 1;
	$doc->{TT}{file_in_charset} = 'utf-8';
	$doc->{TT}{file_out_charset} = 'utf-8';
	# let's cheat a bit to force porefs option to be passed to Locale::Po4a::Po;
	# this is undocument use of internal Locale::Po4a::TransTractor's data,
	# compulsory since this module prevents us from using the porefs option.
	my %po_options = ('porefs' => 'none');
	$doc->{TT}{po_out}=Locale::Po4a::Po->new(\%po_options);
	$doc->{TT}{po_out}->set_charset('utf-8');
	# do the actual work
	$doc->parse;
	$doc->writepo($potfile);
} #}}}

sub refreshpofiles ($@) { #{{{
	my $masterfile=shift;
	my @pofiles=@_;

	my $potfile=potfile($masterfile);
	error("[po/refreshpofiles] POT file ($potfile) does not exist") unless (-e $potfile);

	foreach my $pofile (@pofiles) {
		if (-e $pofile) {
			my $cmd = "msgmerge -U --backup=none $pofile $potfile";
			system ($cmd) == 0
				or error("[po/refreshpofiles:$pofile] failed to update");
		}
		else {
			File::Copy::syscopy($potfile,$pofile)
				or error("[po/refreshpofiles:$pofile] failed to copy the POT file");
		}
	}
} #}}}

sub needsbuild () { #{{{
	my $needsbuild=shift;

	# build %translations, using istranslation's side-effect
	foreach my $page (keys %pagesources) {
		istranslation($page);
	}

	# refresh/create POT and PO files as needed
	my $updated_po_files=0;
	foreach my $page (keys %pagesources) {
		my $pageneedsbuild = grep { $_ eq $pagesources{$page} } @$needsbuild;
		if (istranslatable($page)) {
			my $file=srcfile($pagesources{$page});
			if ($pageneedsbuild || ! -e potfile($file)) {
				refreshpot($file);
			}
			my @pofiles;
			foreach my $lang (keys %{$config{po_slave_languages}}) {
				my $pofile=pofile($file, $lang);
				if ($pageneedsbuild || ! -e $pofile) {
					push @pofiles, $pofile;
				}
			}
			if (@pofiles) {
				refreshpofiles($file, @pofiles) ;
				map { IkiWiki::rcs_add($_); } @pofiles if ($config{rcs});
				$updated_po_files = 1;
			}
		}
	}

	# check staged changes in and trigger a wiki refresh.
	if ($updated_po_files) {
		if ($config{rcs}) {
			IkiWiki::disable_commit_hook();
			IkiWiki::rcs_commit_staged(gettext("updated PO files"),
				"refreshpofiles", "127.0.0.1");
			IkiWiki::enable_commit_hook();
			IkiWiki::rcs_update();
		}
		IkiWiki::refresh();
		IkiWiki::saveindex();
		# refresh module's private variables
		undef %filtered;
		undef %translations;
		foreach my $page (keys %pagesources) {
			istranslation($page);
		}
	}


	# make existing translations depend on the corresponding master page
	foreach my $master (keys %translations) {
		foreach my $slave (values %{$translations{$master}}) {
			add_depends($slave, $master);
		}
	}
} #}}}

sub mytargetpage ($$) { #{{{
	my $page=shift;
	my $ext=shift;

	if (istranslation($page)) {
		my ($masterpage, $lang) = ($page =~ /(.*)[.]([a-z]{2})$/);
		if (! $config{usedirs} || $masterpage eq 'index') {
			return $masterpage . "." . $lang . "." . $ext;
		}
		else {
			return $masterpage . "/index." . $lang . "." . $ext;
		}
	}
	elsif (istranslatable($page)) {
		if (! $config{usedirs} || $page eq 'index') {
			return $page . "." . $config{po_master_language}{code} . "." . $ext;
		}
		else {
			return $page . "/index." . $config{po_master_language}{code} . "." . $ext;
		}
	}
	return $origsubs{'targetpage'}->($page, $ext);
} #}}}

sub mybeautify_urlpath ($) { #{{{
	my $url=shift;
	my $res=$origsubs{'beautify_urlpath'}->($url);
	if ($config{po_link_to} eq "negotiated") {
		$res =~ s!/index.$config{po_master_language}{code}.$config{htmlext}$!/!;
	}
	return $res;
} #}}}

sub urlto_with_orig_beautiful_urlpath($$) { #{{{
	my $to=shift;
	my $from=shift;

	inject(name => "IkiWiki::beautify_urlpath", call => $origsubs{'beautify_urlpath'});
	my $res=urlto($to, $from);
	inject(name => "IkiWiki::beautify_urlpath", call => \&mybeautify_urlpath);

	return $res;
} #}}}

sub mybestlink ($$) { #{{{
	my $page=shift;
	my $link=shift;
	my $res=$origsubs{'bestlink'}->($page, $link);
	if (length $res) {
		if ($config{po_link_to} eq "current"
		    && istranslatable($res)
		    && istranslation($page)) {
			my ($masterpage, $curlang) = ($page =~ /(.*)[.]([a-z]{2})$/);
			return $res . "." . $curlang;
		}
		else {
			return $res;
		}
	}
	return "";
} #}}}

# We use filter to convert PO to the master page's format,
# since the rest of ikiwiki should not work on PO files.
sub filter (@) { #{{{
	my %params = @_;
	my $page = $params{page};
	my $destpage = $params{destpage};
	my $content = decode_utf8(encode_utf8($params{content}));

	return $content if ( ! istranslation($page)
			     || ( exists $filtered{$page}{$destpage}
				  && $filtered{$page}{$destpage} eq 1 ));

	# CRLF line terminators make poor Locale::Po4a feel bad
	$content=~s/\r\n/\n/g;

	# Locale::Po4a needs an input file, and I'm too lazy to learn
	# how to disguise a variable as a file
	my $infile = File::Temp->new(TEMPLATE => "ikiwiki-po-filter-in.XXXXXXXXXX",
				     TMPDIR => 1)->filename;
	writefile(basename($infile), File::Spec->tmpdir, $content);

	my ($masterpage, $lang) = ($page =~ /(.*)[.]([a-z]{2})$/);
	my $masterfile = srcfile($pagesources{$masterpage});
	my (@pos,@masters);
	push @pos,$infile;
	push @masters,$masterfile;
	my %options = (
			"markdown" => (pagetype($masterfile) eq 'mdwn') ? 1 : 0,
			);
	my $doc=Locale::Po4a::Chooser::new('text',%options);
	$doc->process(
		'po_in_name'	=> \@pos,
		'file_in_name'	=> \@masters,
		'file_in_charset'  => 'utf-8',
		'file_out_charset' => 'utf-8',
	) or error("[po/filter:$infile]: failed to translate");
	my $tmpout = File::Temp->new(TEMPLATE => "ikiwiki-po-filter-out.XXXXXXXXXX",
				     TMPDIR => 1)->filename;
	$doc->write($tmpout) or error("[po/filter:$infile] could not write $tmpout");
	$content = readfile($tmpout) or error("[po/filter:$infile] could not read $tmpout");
	$filtered{$page}{$destpage}=1;
	return $content;
} #}}}

sub htmlize (@) { #{{{
	my %params=@_;
	my $page = $params{page};
	my $content = $params{content};
	my ($masterpage, $lang) = ($page =~ /(.*)[.]([a-z]{2})$/);
	my $masterfile = srcfile($pagesources{$masterpage});

	# force content to be htmlize'd as if it was the same type as the master page
	return IkiWiki::htmlize($page, $page, pagetype($masterfile), $content);
} #}}}

sub percenttranslated ($) { #{{{
	my $page=shift;
	return "N/A" unless (istranslation($page));
	my ($masterpage, $lang) = ($page =~ /(.*)[.]([a-z]{2})$/);
	my $file=srcfile($pagesources{$page});
	my $masterfile = srcfile($pagesources{$masterpage});
	my (@pos,@masters);
	push @pos,$file;
	push @masters,$masterfile;
	my %options = (
			"markdown" => (pagetype($masterfile) eq 'mdwn') ? 1 : 0,
			);
	my $doc=Locale::Po4a::Chooser::new('text',%options);
	$doc->process(
		'po_in_name'	=> \@pos,
		'file_in_name'	=> \@masters,
		'file_in_charset'  => 'utf-8',
		'file_out_charset' => 'utf-8',
	) or error("[po/percenttranslated:$file]: failed to translate");
	my ($percent,$hit,$queries) = $doc->stats();
	return $percent;
} #}}}

sub otherlanguages ($) { #{{{
	my $page=shift;
	my @ret;
	if (istranslatable($page)) {
		foreach my $lang (sort keys %{$translations{$page}}) {
			my $translation = $translations{$page}{$lang};
			push @ret, {
				url => urlto($translation, $page),
				code => $lang,
				language => $config{po_slave_languages}{$lang},
				percent => percenttranslated($translation),
			};
		}
	}
	elsif (istranslation($page)) {
		my ($masterpage, $curlang) = ($page =~ /(.*)[.]([a-z]{2})$/);
		push @ret, {
			url => urlto_with_orig_beautiful_urlpath($masterpage, $page),
			code => $config{po_master_language}{code},
			language => $config{po_master_language}{name},
			master => 1,
		};
		foreach my $lang (sort keys %{$translations{$masterpage}}) {
			push @ret, {
				url => urlto($translations{$masterpage}{$lang}, $page),
				code => $lang,
				language => $config{po_slave_languages}{$lang},
				percent => percenttranslated($translations{$masterpage}{$lang}),
			} unless ($lang eq $curlang);
		}
	}
	return @ret;
} #}}}

sub pagetemplate (@) { #{{{
	my %params=@_;
        my $page=$params{page};
        my $destpage=$params{destpage};
        my $template=$params{template};

	if (istranslation($page) && $template->query(name => "percenttranslated")) {
		$template->param(percenttranslated => percenttranslated($page));
	}
	if ($template->query(name => "istranslation")) {
		$template->param(istranslation => istranslation($page));
	}
	if ($template->query(name => "istranslatable")) {
		$template->param(istranslatable => istranslatable($page));
	}
	if ($template->query(name => "otherlanguages")) {
		$template->param(otherlanguages => [otherlanguages($page)]);
		if (istranslatable($page)) {
			foreach my $translation (values %{$translations{$page}}) {
				add_depends($page, $translation);
			}
		}
		elsif (istranslation($page)) {
			my ($masterpage, $curlang) = ($page =~ /(.*)[.]([a-z]{2})$/);
			add_depends($page, $masterpage);
			foreach my $translation (values %{$translations{$masterpage}}) {
				add_depends($page, $translation);
			}
		}
	}
	# Rely on IkiWiki::Render's genpage() to decide wether
	# a discussion link should appear on $page; this is not
	# totally accurate, though: some broken links may be generated
	# when cgiurl is disabled.
	# This compromise avoids some code duplication, and will probably
	# prevent future breakage when ikiwiki internals change.
	# Known limitations are preferred to future random bugs.
	if ($template->param('discussionlink') && istranslation($page)) {
		my ($masterpage, $lang) = ($page =~ /(.*)[.]([a-z]{2})$/);
		$template->param('discussionlink' => htmllink(
							$page,
							$destpage,
							$masterpage . '/' . gettext("Discussion"),
							noimageinline => 1,
							forcesubpage => 0,
							linktext => gettext("Discussion"),
							));
	}
} # }}}

sub editcontent () { #{{{
	my %params=@_;
	# as we're previewing or saving a page, the content may have
	# changed, so tell the next filter() invocation it must not be lazy
	if (exists $filtered{$params{page}}{$params{page}}) {
		delete $filtered{$params{page}}{$params{page}};
	}
	return $params{content};
} #}}}

sub istranslatable ($) { #{{{
	my $page=shift;
	my $file=$pagesources{$page};

	if (! defined $file
	    || (defined pagetype($file) && pagetype($file) eq 'po')
	    || $file =~ /\.pot$/) {
		return 0;
	}
	return pagespec_match($page, $config{po_translatable_pages});
} #}}}

sub _istranslation ($) { #{{{
	my $page=shift;
	my $file=$pagesources{$page};
	if (! defined $file) {
		return IkiWiki::FailReason->new("no file specified");
	}

	if (! defined $file
	    || ! defined pagetype($file)
 	    || ! pagetype($file) eq 'po'
	    || $file =~ /\.pot$/) {
		return 0;
	}

	my ($masterpage, $lang) = ($page =~ /(.*)[.]([a-z]{2})$/);
	if (! defined $masterpage || ! defined $lang
	    || ! (length($masterpage) > 0) || ! (length($lang) > 0)
	    || ! defined $pagesources{$masterpage}
	    || ! defined $config{po_slave_languages}{$lang}) {
		return 0;
	}

	return istranslatable($masterpage);
} #}}}

sub istranslation ($) { #{{{
	my $page=shift;
	if (_istranslation($page)) {
		my ($masterpage, $lang) = ($page =~ /(.*)[.]([a-z]{2})$/);
		$translations{$masterpage}{$lang}=$page unless exists $translations{$masterpage}{$lang};
		return 1;
	}
	return 0;
} #}}}

package IkiWiki::PageSpec;
use warnings;
use strict;
use IkiWiki 2.00;

sub match_istranslation ($;@) { #{{{
	my $page=shift;
	if (IkiWiki::Plugin::po::istranslation($page)) {
		return IkiWiki::SuccessReason->new("is a translation page");
	}
	else {
		return IkiWiki::FailReason->new("is not a translation page");
	}
} #}}}

sub match_istranslatable ($;@) { #{{{
	my $page=shift;
	if (IkiWiki::Plugin::po::istranslatable($page)) {
		return IkiWiki::SuccessReason->new("is set as translatable in po_translatable_pages");
	}
	else {
		return IkiWiki::FailReason->new("is not set as translatable in po_translatable_pages");
	}
} #}}}

sub match_lang ($$;@) { #{{{
	my $page=shift;
	my $wanted=shift;
	my $regexp=IkiWiki::glob2re($wanted);
	my $lang;
	my $masterpage;

	if (IkiWiki::Plugin::po::istranslation($page)) {
		($masterpage, $lang) = ($page =~ /(.*)[.]([a-z]{2})$/);
	}
	else {
		$lang = $config{po_master_language}{code};
	}

	if ($lang!~/^$regexp$/i) {
		return IkiWiki::FailReason->new("file language is $lang, not $wanted");
	}
	else {
		return IkiWiki::SuccessReason->new("file language is $wanted");
	}
} #}}}

sub match_currentlang ($$;@) { #{{{
	my $page=shift;
	shift;
	my %params=@_;
	my ($currentmasterpage, $currentlang, $masterpage, $lang);

	return IkiWiki::FailReason->new("no location provided") unless exists $params{location};

	if (IkiWiki::Plugin::po::istranslation($params{location})) {
		($currentmasterpage, $currentlang) = ($params{location} =~ /(.*)[.]([a-z]{2})$/);
	}
	else {
		$currentlang = $config{po_master_language}{code};
	}

	if (IkiWiki::Plugin::po::istranslation($page)) {
		($masterpage, $lang) = ($page =~ /(.*)[.]([a-z]{2})$/);
	}
	else {
		$lang = $config{po_master_language}{code};
	}

	if ($lang eq $currentlang) {
		return IkiWiki::SuccessReason->new("file language is the same as current one, i.e. $currentlang");
	}
	else {
		return IkiWiki::FailReason->new("file language is $lang, whereas current language is $currentlang");
	}
} #}}}

1
