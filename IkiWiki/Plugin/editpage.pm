#!/usr/bin/perl
package IkiWiki::Plugin::editpage;

use warnings;
use strict;
use IkiWiki;
use open qw{:utf8 :std};

sub import { #{{{
	hook(type => "getsetup", id => "editpage", call => \&getsetup);
        hook(type => "sessioncgi", id => "editpage", call => \&IkiWiki::cgi_editpage);
} # }}}

sub getsetup () { #{{{
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
} #}}}

# Back to ikiwiki namespace for the rest, this code is very much
# internal to ikiwiki even though it's separated into a plugin,
# and other plugins use the functions below.
package IkiWiki;

sub check_canedit ($$$;$) { #{{{
	my $page=shift;
	my $q=shift;
	my $session=shift;
	my $nonfatal=shift;
	
	my $canedit;
	run_hooks(canedit => sub {
		return if defined $canedit;
		my $ret=shift->($page, $q, $session);
		if (defined $ret) {
			if ($ret eq "") {
				$canedit=1;
			}
			elsif (ref $ret eq 'CODE') {
				$ret->() unless $nonfatal;
				$canedit=0;
			}
			elsif (defined $ret) {
				error($ret) unless $nonfatal;
				$canedit=0;
			}
		}
	});
	return $canedit;
} #}}}

sub cgi_editpage ($$) { #{{{
	my $q=shift;
	my $session=shift;
	
        my $do=$q->param('do');
	return unless $do eq 'create' || $do eq 'edit';

	decode_cgi_utf8($q);

	my @fields=qw(do rcsinfo subpage from page type editcontent comments);
	my @buttons=("Save Page", "Preview", "Cancel");
	eval q{use CGI::FormBuilder};
	error($@) if $@;
	my $form = CGI::FormBuilder->new(
		fields => \@fields,
		charset => "utf-8",
		method => 'POST',
		required => [qw{editcontent}],
		javascript => 0,
		params => $q,
		action => $config{cgiurl},
		header => 0,
		table => 0,
		template => scalar template_params("editpage.tmpl"),
		wikiname => $config{wikiname},
	);
	
	decode_form_utf8($form);
	run_hooks(formbuilder_setup => sub {
		shift->(form => $form, cgi => $q, session => $session,
			buttons => \@buttons);
	});
	decode_form_utf8($form);
	
	# This untaint is safe because we check file_pruned and
	# wiki_file_regexp.
	my ($page)=$form->field('page')=~/$config{wiki_file_regexp}/;
	$page=possibly_foolish_untaint($page);
	my $absolute=($page =~ s#^/+##);
	if (! defined $page || ! length $page ||
	    file_pruned($page, $config{srcdir})) {
		error("bad page name");
	}

	my $baseurl = urlto($page, undef, 1);

	my $from;
	if (defined $form->field('from')) {
		($from)=$form->field('from')=~/$config{wiki_file_regexp}/;
	}
	
	my $file;
	my $type;
	if (exists $pagesources{$page} && $form->field("do") ne "create") {
		$file=$pagesources{$page};
		$type=pagetype($file);
		if (! defined $type || $type=~/^_/) {
			error(sprintf(gettext("%s is not an editable page"), $page));
		}
		if (! $form->submitted) {
			$form->field(name => "rcsinfo",
				value => rcs_prepedit($file), force => 1);
		}
		$form->field(name => "editcontent", validate => '/.*/');
	}
	else {
		$type=$form->param('type');
		if (defined $type && length $type && $hooks{htmlize}{$type}) {
			$type=possibly_foolish_untaint($type);
		}
		elsif (defined $from && exists $pagesources{$from}) {
			# favor the type of linking page
			$type=pagetype($pagesources{$from});
		}
		$type=$config{default_pageext} unless defined $type;
		$file=$page.".".$type;
		if (! $form->submitted) {
			$form->field(name => "rcsinfo", value => "", force => 1);
		}
		$form->field(name => "editcontent", validate => '/.+/');
	}

	$form->field(name => "do", type => 'hidden');
	$form->field(name => "sid", type => "hidden", value => $session->id,
		force => 1);
	$form->field(name => "from", type => 'hidden');
	$form->field(name => "rcsinfo", type => 'hidden');
	$form->field(name => "subpage", type => 'hidden');
	$form->field(name => "page", value => $page, force => 1);
	$form->field(name => "type", value => $type, force => 1);
	$form->field(name => "comments", type => "text", size => 80);
	$form->field(name => "editcontent", type => "textarea", rows => 20,
		cols => 80);
	$form->tmpl_param("can_commit", $config{rcs});
	$form->tmpl_param("indexlink", indexlink());
	$form->tmpl_param("helponformattinglink",
		htmllink($page, $page, "ikiwiki/formatting",
			noimageinline => 1,
			linktext => "FormattingHelp"));
	
	if ($form->submitted eq "Cancel") {
		if ($form->field("do") eq "create" && defined $from) {
			redirect($q, urlto($from, undef, 1));
		}
		elsif ($form->field("do") eq "create") {
			redirect($q, $config{url});
		}
		else {
			redirect($q, urlto($page, undef, 1));
		}
		exit;
	}
	elsif ($form->submitted eq "Preview") {
		my $new=not exists $pagesources{$page};
		if ($new) {
			# temporarily record its type
			$pagesources{$page}=$page.".".$type;
		}

		my $content=$form->field('editcontent');

		run_hooks(editcontent => sub {
			$content=shift->(
				content => $content,
				page => $page,
				cgi => $q,
				session => $session,
			);
		});
		my $preview=htmlize($page, $page, $type,
			linkify($page, $page,
			preprocess($page, $page,
			filter($page, $page, $content), 0, 1)));
		run_hooks(format => sub {
			$preview=shift->(
				page => $page,
				content => $preview,
			);
		});
		$form->tmpl_param("page_preview", $preview);
	
		if ($new) {
			delete $pagesources{$page};
		}
		# previewing may have created files on disk
		saveindex();
	}
	elsif ($form->submitted eq "Save Page") {
		$form->tmpl_param("page_preview", "");
	}
	
	if ($form->submitted ne "Save Page" || ! $form->validate) {
		if ($form->field("do") eq "create") {
			my @page_locs;
			my $best_loc;
			if (! defined $from || ! length $from ||
			    $from ne $form->field('from') ||
			    file_pruned($from, $config{srcdir}) ||
			    $from=~/^\// || 
			    $absolute ||
			    $form->submitted eq "Preview") {
				@page_locs=$best_loc=$page;
			}
			else {
				my $dir=$from."/";
				$dir=~s![^/]+/+$!!;
				
				if ((defined $form->field('subpage') && length $form->field('subpage')) ||
				    $page eq gettext('discussion')) {
					$best_loc="$from/$page";
				}
				else {
					$best_loc=$dir.$page;
				}
				
				push @page_locs, $dir.$page;
				push @page_locs, "$from/$page";
				while (length $dir) {
					$dir=~s![^/]+/+$!!;
					push @page_locs, $dir.$page;
				}
			
				push @page_locs, "$config{userdir}/$page"
					if length $config{userdir};
			}

			@page_locs = grep {
				! exists $pagecase{lc $_}
			} @page_locs;
			if (! @page_locs) {
				# hmm, someone else made the page in the
				# meantime?
				if ($form->submitted eq "Preview") {
					# let them go ahead with the edit
					# and resolve the conflict at save
					# time
					@page_locs=$page;
				}
				else {
					redirect($q, urlto($page, undef, 1));
					exit;
				}
			}

			my @editable_locs = grep {
				check_canedit($_, $q, $session, 1)
			} @page_locs;
			if (! @editable_locs) {
				# let it throw an error this time
				map { check_canedit($_, $q, $session) } @page_locs;
			}
			
			my @page_types;
			if (exists $hooks{htmlize}) {
				@page_types=grep { !/^_/ }
					keys %{$hooks{htmlize}};
			}
			
			$form->tmpl_param("page_select", 1);
			$form->field(name => "page", type => 'select',
				options => [ map { [ $_, pagetitle($_, 1) ] } @editable_locs ],
				value => $best_loc);
			$form->field(name => "type", type => 'select',
				options => \@page_types);
			$form->title(sprintf(gettext("creating %s"), pagetitle($page)));
			
		}
		elsif ($form->field("do") eq "edit") {
			check_canedit($page, $q, $session);
			if (! defined $form->field('editcontent') || 
			    ! length $form->field('editcontent')) {
				my $content="";
				if (exists $pagesources{$page}) {
					$content=readfile(srcfile($pagesources{$page}));
					$content=~s/\n/\r\n/g;
				}
				$form->field(name => "editcontent", value => $content,
					force => 1);
			}
			$form->tmpl_param("page_select", 0);
			$form->field(name => "page", type => 'hidden');
			$form->field(name => "type", type => 'hidden');
			$form->title(sprintf(gettext("editing %s"), pagetitle($page)));
		}
		
		showform($form, \@buttons, $session, $q, forcebaseurl => $baseurl);
	}
	else {
		# save page
		check_canedit($page, $q, $session);
	
		# The session id is stored on the form and checked to
		# guard against CSRF. But only if the user is logged in,
		# as anonok can allow anonymous edits.
		if (defined $session->param("name")) {
			my $sid=$q->param('sid');
			if (! defined $sid || $sid ne $session->id) {
				error(gettext("Your login session has expired."));
			}
		}

		my $exists=-e "$config{srcdir}/$file";

		if ($form->field("do") ne "create" && ! $exists &&
		    ! defined srcfile($file, 1)) {
			$form->tmpl_param("message", template("editpagegone.tmpl")->output);
			$form->field(name => "do", value => "create", force => 1);
			$form->tmpl_param("page_select", 0);
			$form->field(name => "page", type => 'hidden');
			$form->field(name => "type", type => 'hidden');
			$form->title(sprintf(gettext("editing %s"), $page));
			showform($form, \@buttons, $session, $q, forcebaseurl => $baseurl);
			exit;
		}
		elsif ($form->field("do") eq "create" && $exists) {
			$form->tmpl_param("message", template("editcreationconflict.tmpl")->output);
			$form->field(name => "do", value => "edit", force => 1);
			$form->tmpl_param("page_select", 0);
			$form->field(name => "page", type => 'hidden');
			$form->field(name => "type", type => 'hidden');
			$form->title(sprintf(gettext("editing %s"), $page));
			$form->field("editcontent", 
				value => readfile("$config{srcdir}/$file").
				         "\n\n\n".$form->field("editcontent"),
				force => 1);
			showform($form, \@buttons, $session, $q, forcebaseurl => $baseurl);
			exit;
		}
		
		my $content=$form->field('editcontent');
		run_hooks(editcontent => sub {
			$content=shift->(
				content => $content,
				page => $page,
				cgi => $q,
				session => $session,
			);
		});
		$content=~s/\r\n/\n/g;
		$content=~s/\r/\n/g;
		$content.="\n" if $content !~ /\n$/;

		$config{cgi}=0; # avoid cgi error message
		eval { writefile($file, $config{srcdir}, $content) };
		$config{cgi}=1;
		if ($@) {
			$form->field(name => "rcsinfo", value => rcs_prepedit($file),
				force => 1);
			my $mtemplate=template("editfailedsave.tmpl");
			$mtemplate->param(error_message => $@);
			$form->tmpl_param("message", $mtemplate->output);
			$form->field("editcontent", value => $content, force => 1);
			$form->tmpl_param("page_select", 0);
			$form->field(name => "page", type => 'hidden');
			$form->field(name => "type", type => 'hidden');
			$form->title(sprintf(gettext("editing %s"), $page));
			showform($form, \@buttons, $session, $q,
				forcebaseurl => $baseurl);
			exit;
		}
		
		my $conflict;
		if ($config{rcs}) {
			my $message="";
			if (defined $form->field('comments') &&
			    length $form->field('comments')) {
				$message=$form->field('comments');
			}
			
			if (! $exists) {
				rcs_add($file);
			}

			# Prevent deadlock with post-commit hook by
			# signaling to it that it should not try to
			# do anything.
			disable_commit_hook();
			$conflict=rcs_commit($file, $message,
				$form->field("rcsinfo"),
				$session->param("name"), $ENV{REMOTE_ADDR});
			enable_commit_hook();
			rcs_update();
		}
		
		# Refresh even if there was a conflict, since other changes
		# may have been committed while the post-commit hook was
		# disabled.
		require IkiWiki::Render;
		refresh();
		saveindex();

		if (defined $conflict) {
			$form->field(name => "rcsinfo", value => rcs_prepedit($file),
				force => 1);
			$form->tmpl_param("message", template("editconflict.tmpl")->output);
			$form->field("editcontent", value => $conflict, force => 1);
			$form->field("do", "edit", force => 1);
			$form->tmpl_param("page_select", 0);
			$form->field(name => "page", type => 'hidden');
			$form->field(name => "type", type => 'hidden');
			$form->title(sprintf(gettext("editing %s"), $page));
			showform($form, \@buttons, $session, $q,
				forcebaseurl => $baseurl);
		}
		else {
			# The trailing question mark tries to avoid broken
			# caches and get the most recent version of the page.
			redirect($q, urlto($page, undef, 1)."?updated");
		}
	}

	exit;
} #}}}

1
