#!/usr/bin/perl

use warnings;
use strict;
use IkiWiki;
use IkiWiki::UserInfo;
use open qw{:utf8 :std};
use Encode;

package IkiWiki;

sub printheader ($) { #{{{
	my $session=shift;
	
	if ($config{sslcookie}) {
		print $session->header(-charset => 'utf-8',
			-cookie => $session->cookie(-secure => 1));
	} else {
		print $session->header(-charset => 'utf-8');
	}

} #}}}

sub showform ($$$$) { #{{{
	my $form=shift;
	my $buttons=shift;
	my $session=shift;
	my $cgi=shift;

	if (exists $hooks{formbuilder}) {
		run_hooks(formbuilder => sub {
			shift->(form => $form, cgi => $cgi, session => $session,
				buttons => $buttons);
		});
	}

	printheader($session);
	print misctemplate($form->title, $form->render(submit => $buttons));
}

sub redirect ($$) { #{{{
	my $q=shift;
	my $url=shift;
	if (! $config{w3mmode}) {
		print $q->redirect($url);
	}
	else {
		print "Content-type: text/plain\n";
		print "W3m-control: GOTO $url\n\n";
	}
} #}}}

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

sub decode_cgi_utf8 ($) { #{{{
	my $cgi = shift;
	foreach my $f ($cgi->param) {
		$cgi->param($f, map { decode_utf8 $_ } $cgi->param($f));
	}
} #}}}

# Check if the user is signed in. If not, redirect to the signin form and
# save their place to return to later.
sub needsignin ($$) { #{{{
	my $q=shift;
	my $session=shift;

	if (! defined $session->param("name") ||
	    ! userinfo_get($session->param("name"), "regdate")) {
		$session->param(postsignin => $ENV{QUERY_STRING});
		cgi_signin($q, $session);
		cgi_savesession($session);
		exit;
	}
} #}}}	

sub cgi_signin ($$) { #{{{
	my $q=shift;
	my $session=shift;

	decode_cgi_utf8($q);
	eval q{use CGI::FormBuilder};
	error($@) if $@;
	my $form = CGI::FormBuilder->new(
		title => "signin",
		name => "signin",
		charset => "utf-8",
		method => 'POST',
		required => 'NONE',
		javascript => 0,
		params => $q,
		action => $config{cgiurl},
		header => 0,
		template => {type => 'div'},
		stylesheet => baseurl()."style.css",
	);
	my $buttons=["Login"];
	
	if ($q->param("do") ne "signin" && !$form->submitted) {
		$form->text(gettext("You need to log in first."));
	}
	$form->field(name => "do", type => "hidden", value => "signin",
		force => 1);
	
	run_hooks(formbuilder_setup => sub {
		shift->(form => $form, cgi => $q, session => $session,
		        buttons => $buttons);
	});

	if ($form->submitted) {
		$form->validate;
	}

	showform($form, $buttons, $session, $q);
} #}}}

sub cgi_postsignin ($$) { #{{{
	my $q=shift;
	my $session=shift;
	
	# Continue with whatever was being done before the signin process.
	if (defined $session->param("postsignin")) {
		my $postsignin=CGI->new($session->param("postsignin"));
		$session->clear("postsignin");
		cgi($postsignin, $session);
		cgi_savesession($session);
		exit;
	}
	else {
		error(gettext("login failed, perhaps you need to turn on cookies?"));
	}
} #}}}

sub cgi_prefs ($$) { #{{{
	my $q=shift;
	my $session=shift;

	needsignin($q, $session);

	decode_cgi_utf8($q);
	eval q{use CGI::FormBuilder};
	error($@) if $@;
	my $form = CGI::FormBuilder->new(
		title => "preferences",
		name => "preferences",
		header => 0,
		charset => "utf-8",
		method => 'POST',
		validate => {
			email => 'EMAIL',
		},
		required => 'NONE',
		javascript => 0,
		params => $q,
		action => $config{cgiurl},
		template => {type => 'div'},
		stylesheet => baseurl()."style.css",
		fieldsets => [
			[login => gettext("Login")],
			[preferences => gettext("Preferences")],
			[admin => gettext("Admin")]
		],
	);
	my $buttons=["Save Preferences", "Logout", "Cancel"];

	run_hooks(formbuilder_setup => sub {
		shift->(form => $form, cgi => $q, session => $session,
		        buttons => $buttons);
	});
	
	$form->field(name => "do", type => "hidden");
	$form->field(name => "email", size => 50, fieldset => "preferences");
	$form->field(name => "banned_users", size => 50,
		fieldset => "admin");
	
	my $user_name=$session->param("name");
	if (! is_admin($user_name)) {
		$form->field(name => "banned_users", type => "hidden");
	}

	if (! $form->submitted) {
		$form->field(name => "email", force => 1,
			value => userinfo_get($user_name, "email"));
		if (is_admin($user_name)) {
			$form->field(name => "banned_users", force => 1,
				value => join(" ", get_banned_users()));
		}
	}
	
	if ($form->submitted eq 'Logout') {
		$session->delete();
		redirect($q, $config{url});
		return;
	}
	elsif ($form->submitted eq 'Cancel') {
		redirect($q, $config{url});
		return;
	}
	elsif ($form->submitted eq 'Save Preferences' && $form->validate) {
		if (defined $form->field('email')) {
			userinfo_set($user_name, 'email', $form->field('email')) ||
				error("failed to set email");
		}
		if (is_admin($user_name)) {
			set_banned_users(grep { ! is_admin($_) }
					split(' ',
						$form->field("banned_users"))) ||
				error("failed saving changes");
		}
		$form->text(gettext("Preferences saved."));
	}
	
	showform($form, $buttons, $session, $q);
} #}}}

sub cgi_editpage ($$) { #{{{
	my $q=shift;
	my $session=shift;

	my @fields=qw(do rcsinfo subpage from page type editcontent comments);
	my @buttons=("Save Page", "Preview", "Cancel");
	
	decode_cgi_utf8($q);
	eval q{use CGI::FormBuilder};
	error($@) if $@;
	my $form = CGI::FormBuilder->new(
		title => "editpage",
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
	
	run_hooks(formbuilder_setup => sub {
		shift->(form => $form, cgi => $q, session => $session,
			buttons => \@buttons);
	});
	
	# This untaint is safe because titlepage removes any problematic
	# characters.
	my ($page)=$form->field('page');
	$page=titlepage(possibly_foolish_untaint($page));
	if (! defined $page || ! length $page ||
	    file_pruned($page, $config{srcdir}) || $page=~/^\//) {
		error("bad page name");
	}
	
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
	$form->field(name => "from", type => 'hidden');
	$form->field(name => "rcsinfo", type => 'hidden');
	$form->field(name => "subpage", type => 'hidden');
	$form->field(name => "page", value => pagetitle($page, 1), force => 1);
	$form->field(name => "type", value => $type, force => 1);
	$form->field(name => "comments", type => "text", size => 80);
	$form->field(name => "editcontent", type => "textarea", rows => 20,
		cols => 80);
	$form->tmpl_param("can_commit", $config{rcs});
	$form->tmpl_param("indexlink", indexlink());
	$form->tmpl_param("helponformattinglink",
		htmllink("", "", "ikiwiki/formatting",
			noimageinline => 1,
			linktext => "FormattingHelp"));
	$form->tmpl_param("baseurl", baseurl());
	
	if ($form->submitted eq "Cancel") {
		if ($form->field("do") eq "create" && defined $from) {
			redirect($q, "$config{url}/".htmlpage($from));
		}
		elsif ($form->field("do") eq "create") {
			redirect($q, $config{url});
		}
		else {
			redirect($q, "$config{url}/".htmlpage($page));
		}
		return;
	}
	elsif ($form->submitted eq "Preview") {
		my $content=$form->field('editcontent');
		run_hooks(editcontent => sub {
			$content=shift->(
				content => $content,
				page => $page,
				cgi => $q,
				session => $session,
			);
		});
		$form->tmpl_param("page_preview",
			htmlize($page, $type,
			linkify($page, "/",
			preprocess($page, "/",
			filter($page, "/", $content), 0, 1))));
		# previewing may have created files on disk
		saveindex();
	}
	elsif ($form->submitted eq "Save Page") {
		$form->tmpl_param("page_preview", "");
	}
	$form->tmpl_param("page_conflict", "");
	
	if ($form->submitted ne "Save Page" || ! $form->validate) {
		if ($form->field("do") eq "create") {
			my @page_locs;
			my $best_loc;
			if (! defined $from || ! length $from ||
			    $from ne $form->field('from') ||
			    file_pruned($from, $config{srcdir}) ||
			    $from=~/^\// ||
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
					redirect($q, "$config{url}/".htmlpage($page));
					return;
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
				options => [ map { pagetitle($_, 1) } @editable_locs ],
				value => pagetitle($best_loc, 1));
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
		
		showform($form, \@buttons, $session, $q);
	}
	else {
		# save page
		check_canedit($page, $q, $session);

		my $exists=-e "$config{srcdir}/$file";

		if ($form->field("do") ne "create" && ! $exists &&
		    ! eval { srcfile($file) }) {
			$form->tmpl_param("page_gone", 1);
			$form->field(name => "do", value => "create", force => 1);
			$form->tmpl_param("page_select", 0);
			$form->field(name => "page", type => 'hidden');
			$form->field(name => "type", type => 'hidden');
			$form->title(sprintf(gettext("editing %s"), $page));
			showform($form, \@buttons, $session, $q);
			return;
		}
		elsif ($form->field("do") eq "create" && $exists) {
			$form->tmpl_param("creation_conflict", 1);
			$form->field(name => "do", value => "edit", force => 1);
			$form->tmpl_param("page_select", 0);
			$form->field(name => "page", type => 'hidden');
			$form->field(name => "type", type => 'hidden');
			$form->title(sprintf(gettext("editing %s"), $page));
			$form->field("editcontent", 
				value => readfile("$config{srcdir}/$file").
				         "\n\n\n".$form->field("editcontent"),
				force => 1);
			showform($form, \@buttons, $session, $q);
			return;
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
			$form->tmpl_param("failed_save", 1);
			$form->tmpl_param("error_message", $@);
			$form->field("editcontent", value => $content, force => 1);
			$form->tmpl_param("page_select", 0);
			$form->field(name => "page", type => 'hidden');
			$form->field(name => "type", type => 'hidden');
			$form->title(sprintf(gettext("editing %s"), $page));
			showform($form, \@buttons, $session, $q);
			return;
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
			$form->tmpl_param("page_conflict", 1);
			$form->field("editcontent", value => $conflict, force => 1);
			$form->field("do", "edit", force => 1);
			$form->tmpl_param("page_select", 0);
			$form->field(name => "page", type => 'hidden');
			$form->field(name => "type", type => 'hidden');
			$form->title(sprintf(gettext("editing %s"), $page));
			showform($form, \@buttons, $session, $q);
			return;
		}
		else {
			# The trailing question mark tries to avoid broken
			# caches and get the most recent version of the page.
			redirect($q, "$config{url}/".htmlpage($page)."?updated");
		}
	}
} #}}}

sub cgi_getsession ($) { #{{{
	my $q=shift;

	eval q{use CGI::Session};
	CGI::Session->name("ikiwiki_session_".encode_utf8($config{wikiname}));
	
	my $oldmask=umask(077);
	my $session = CGI::Session->new("driver:DB_File", $q,
		{ FileName => "$config{wikistatedir}/sessions.db" });
	umask($oldmask);

	return $session;
} #}}}

sub cgi_savesession ($) { #{{{
	my $session=shift;

	# Force session flush with safe umask.
	my $oldmask=umask(077);
	$session->flush;
	umask($oldmask);
} #}}}

sub cgi (;$$) { #{{{
	my $q=shift;
	my $session=shift;

	if (! $q) {
		eval q{use CGI};
		error($@) if $@;
	
		$q=CGI->new;
	
		run_hooks(cgi => sub { shift->($q) });
	}

	my $do=$q->param('do');
	if (! defined $do || ! length $do) {
		my $error = $q->cgi_error;
		if ($error) {
			error("Request not processed: $error");
		}
		else {
			error("\"do\" parameter missing");
		}
	}
	
	# Need to lock the wiki before getting a session.
	lockwiki();
	loadindex();
	
	if (! $session) {
		$session=cgi_getsession($q);
	}
	
	# Auth hooks can sign a user in.
	if ($do ne 'signin' && ! defined $session->param("name")) {
		run_hooks(auth => sub {
			shift->($q, $session)
		});
		if (defined $session->param("name")) {
			# Make sure whatever user was authed is in the
			# userinfo db.
			if (! userinfo_get($session->param("name"), "regdate")) {
				userinfo_setall($session->param("name"), {
					email => "",
					password => "",
					regdate => time,
				}) || error("failed adding user");
			}
		}
	}
	
	if (defined $session->param("name") &&
	    userinfo_get($session->param("name"), "banned")) {
		print $q->header(-status => "403 Forbidden");
		$session->delete();
		print gettext("You are banned.");
		cgi_savesession($session);
	}

	run_hooks(sessioncgi => sub { shift->($q, $session) });

	if ($do eq 'signin') {
		cgi_signin($q, $session);
		cgi_savesession($session);
	}
	elsif ($do eq 'prefs') {
		cgi_prefs($q, $session);
	}
	elsif ($do eq 'create' || $do eq 'edit') {
		cgi_editpage($q, $session);
	}
	elsif (defined $session->param("postsignin") || $do eq 'postsignin') {
		cgi_postsignin($q, $session);
	}
	else {
		error("unknown do parameter");
	}
} #}}}

1