#!/usr/bin/perl

package IkiWiki;

use warnings;
use strict;
use IkiWiki;
use IkiWiki::UserInfo;
use open qw{:utf8 :std};
use Encode;

sub printheader ($) { #{{{
	my $session=shift;
	
	if ($config{sslcookie}) {
		print $session->header(-charset => 'utf-8',
			-cookie => $session->cookie(-secure => 1));
	} else {
		print $session->header(-charset => 'utf-8');
	}
} #}}}

sub showform ($$$$;@) { #{{{
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
	print misctemplate($form->title, $form->render(submit => $buttons), @_);
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
	# decode_form_utf8 method is needed for 5.10
	if ($] < 5.01) {
		my $cgi = shift;
		foreach my $f ($cgi->param) {
			$cgi->param($f, map { decode_utf8 $_ } $cgi->param($f));
		}
	}
} #}}}

sub decode_form_utf8 ($) { #{{{
	if ($] >= 5.01) {
		my $form = shift;
		foreach my $f ($form->field) {
			$form->field(name  => $f,
			             value => decode_utf8($form->field($f)),
		                     force => 1,
			);
		}
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
	
	decode_form_utf8($form);
	run_hooks(formbuilder_setup => sub {
		shift->(form => $form, cgi => $q, session => $session,
		        buttons => $buttons);
	});
	decode_form_utf8($form);

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
	
	# The session id is stored on the form and checked to
	# guard against CSRF.
	my $sid=$q->param('sid');
	if (! defined $sid) {
		$q->delete_all;
	}
	elsif ($sid ne $session->id) {
		error(gettext("Your login session has expired."));
	}

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
	
	decode_form_utf8($form);
	run_hooks(formbuilder_setup => sub {
		shift->(form => $form, cgi => $q, session => $session,
		        buttons => $buttons);
	});
	decode_form_utf8($form);
	
	$form->field(name => "do", type => "hidden", value => "prefs",
		force => 1);
	$form->field(name => "sid", type => "hidden", value => $session->id,
		force => 1);
	$form->field(name => "email", size => 50, fieldset => "preferences");
	
	my $user_name=$session->param("name");

	# XXX deprecated, should be removed eventually
	$form->field(name => "banned_users", size => 50, fieldset => "admin");
	if (! is_admin($user_name)) {
		$form->field(name => "banned_users", type => "hidden");
	}
	if (! $form->submitted) {
		$form->field(name => "email", force => 1,
			value => userinfo_get($user_name, "email"));
		if (is_admin($user_name)) {
			my $value=join(" ", get_banned_users());
			if (length $value) {
				$form->field(name => "banned_users", force => 1,
					value => join(" ", get_banned_users()),
					comment => "deprecated; please move to banned_users in setup file");
			}
			else {
				$form->field(name => "banned_users", type => "hidden");
			}
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

		# XXX deprecated, should be removed eventually
		if (is_admin($user_name)) {
			set_banned_users(grep { ! is_admin($_) }
					split(' ',
						$form->field("banned_users"))) ||
				error("failed saving changes");
			if (! length $form->field("banned_users")) {
				$form->field(name => "banned_users", type => "hidden");
			}
		}

		$form->text(gettext("Preferences saved."));
	}
	
	showform($form, $buttons, $session, $q);
} #}}}

sub cgi_editpage ($$) { #{{{
	my $q=shift;
	my $session=shift;
	
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
	
	# This untaint is safe because we check file_pruned.
	my $page=$form->field('page');
	$page=possibly_foolish_untaint($page);
	my $absolute=($page =~ s#^/+##);
	if (! defined $page || ! length $page ||
	    file_pruned($page, $config{srcdir})) {
		error("bad page name");
	}

	my $baseurl=$config{url}."/".htmlpage($page);
	
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
			return;
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
			$form->tmpl_param("message", template("editconflict.tmpl")->output);
			$form->field("editcontent", value => $conflict, force => 1);
			$form->field("do", "edit", force => 1);
			$form->tmpl_param("page_select", 0);
			$form->field(name => "page", type => 'hidden');
			$form->field(name => "type", type => 'hidden');
			$form->title(sprintf(gettext("editing %s"), $page));
			showform($form, \@buttons, $session, $q,
				forcebaseurl => $baseurl);
			return;
		}
		else {
			# The trailing question mark tries to avoid broken
			# caches and get the most recent version of the page.
			redirect($q, "$config{url}/".htmlpage($page)."?updated");
		}
	}
} #}}}
	
sub check_banned ($$) { #{{{
	my $q=shift;
	my $session=shift;

	my $name=$session->param("name");
	if (defined $name) {
		# XXX banned in userinfo is deprecated, should be removed
		# eventually, and only banned_users be checked.
		if (userinfo_get($session->param("name"), "banned") ||
		    grep { $name eq $_ } @{$config{banned_users}}) {
			print $q->header(-status => "403 Forbidden");
			$session->delete();
			print gettext("You are banned.");
			cgi_savesession($session);
			exit;
		}
	}
}

sub cgi_getsession ($) { #{{{
	my $q=shift;

	eval q{use CGI::Session};
	error($@) if $@;
	CGI::Session->name("ikiwiki_session_".encode_utf8($config{wikiname}));
	
	my $oldmask=umask(077);
	my $session = eval {
		CGI::Session->new("driver:DB_File", $q,
			{ FileName => "$config{wikistatedir}/sessions.db" })
	};
	if (! $session || $@) {
		error($@." ".CGI::Session->errstr());
	}
	
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

	eval q{use CGI};
	error($@) if $@;
	$CGI::DISABLE_UPLOADS=$config{cgi_disable_uploads};

	if (! $q) {
		binmode(STDIN);
		$q=CGI->new;
		binmode(STDIN, ":utf8");
	
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
	
	check_banned($q, $session);
	
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

# Does not need tobe called directly; all errors will go through here.
sub cgierror ($) { #{{{
	my $message=shift;

	print "Content-type: text/html\n\n";
	print misctemplate(gettext("Error"),
		"<p class=\"error\">".gettext("Error").": $message</p>");
	die $@;
} #}}}

1
