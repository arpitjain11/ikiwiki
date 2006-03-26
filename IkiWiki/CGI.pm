#!/usr/bin/perl

use warnings;
use strict;

package IkiWiki;

sub page_locked ($$;$) { #{{{
	my $page=shift;
	my $session=shift;
	my $nonfatal=shift;
	
	my $user=$session->param("name");
	return if length $user && is_admin($user);

	foreach my $admin (@{$config{adminuser}}) {
		my $locked_pages=userinfo_get($admin, "locked_pages");
		if (globlist_match($page, userinfo_get($admin, "locked_pages"))) {
			return 1 if $nonfatal;
			error(htmllink("", $page, 1)." is locked by ".
			      htmllink("", $admin, 1)." and cannot be edited.");
		}
	}

	return 0;
} #}}}

sub cgi_recentchanges ($) { #{{{
	my $q=shift;
	
	unlockwiki();

	my $template=HTML::Template->new(
		filename => "$config{templatedir}/recentchanges.tmpl"
	);
	$template->param(
		title => "RecentChanges",
		indexlink => indexlink(),
		wikiname => $config{wikiname},
		changelog => [rcs_recentchanges(100)],
	);
	print $q->header, $template->output;
} #}}}

sub cgi_signin ($$) { #{{{
	my $q=shift;
	my $session=shift;

	eval q{use CGI::FormBuilder};
	my $form = CGI::FormBuilder->new(
		title => "signin",
		fields => [qw(do title page subpage from name password confirm_password email)],
		header => 1,
		method => 'POST',
		validate => {
			confirm_password => {
				perl => q{eq $form->field("password")},
			},
			email => 'EMAIL',
		},
		required => 'NONE',
		javascript => 0,
		params => $q,
		action => $q->request_uri,
		header => 0,
		template => (-e "$config{templatedir}/signin.tmpl" ?
		              "$config{templatedir}/signin.tmpl" : "")
	);
	
	$form->field(name => "name", required => 0);
	$form->field(name => "do", type => "hidden");
	$form->field(name => "page", type => "hidden");
	$form->field(name => "title", type => "hidden");
	$form->field(name => "from", type => "hidden");
	$form->field(name => "subpage", type => "hidden");
	$form->field(name => "password", type => "password", required => 0);
	$form->field(name => "confirm_password", type => "password", required => 0);
	$form->field(name => "email", required => 0);
	if ($q->param("do") ne "signin") {
		$form->text("You need to log in first.");
	}
	
	if ($form->submitted) {
		# Set required fields based on how form was submitted.
		my %required=(
			"Login" => [qw(name password)],
			"Register" => [qw(name password confirm_password email)],
			"Mail Password" => [qw(name)],
		);
		foreach my $opt (@{$required{$form->submitted}}) {
			$form->field(name => $opt, required => 1);
		}
	
		# Validate password differently depending on how
		# form was submitted.
		if ($form->submitted eq 'Login') {
			$form->field(
				name => "password",
				validate => sub {
					length $form->field("name") &&
					shift eq userinfo_get($form->field("name"), 'password');
				},
			);
			$form->field(name => "name", validate => '/^\w+$/');
		}
		else {
			$form->field(name => "password", validate => 'VALUE');
		}
		# And make sure the entered name exists when logging
		# in or sending email, and does not when registering.
		if ($form->submitted eq 'Register') {
			$form->field(
				name => "name",
				validate => sub {
					my $name=shift;
					length $name &&
					! userinfo_get($name, "regdate");
				},
			);
		}
		else {
			$form->field(
				name => "name",
				validate => sub {
					my $name=shift;
					length $name &&
					userinfo_get($name, "regdate");
				},
			);
		}
	}
	else {
		# First time settings.
		$form->field(name => "name", comment => "use FirstnameLastName");
		$form->field(name => "confirm_password", comment => "(only needed");
		$form->field(name => "email",            comment => "for registration)");
		if ($session->param("name")) {
			$form->field(name => "name", value => $session->param("name"));
		}
	}

	if ($form->submitted && $form->validate) {
		if ($form->submitted eq 'Login') {
			$session->param("name", $form->field("name"));
			if (defined $form->field("do") && 
			    $form->field("do") ne 'signin') {
				print $q->redirect(
					"$config{cgiurl}?do=".$form->field("do").
					"&page=".$form->field("page").
					"&title=".$form->field("title").
					"&subpage=".$form->field("subpage").
					"&from=".$form->field("from"));;
			}
			else {
				print $q->redirect($config{url});
			}
		}
		elsif ($form->submitted eq 'Register') {
			my $user_name=$form->field('name');
			if (userinfo_setall($user_name, {
				           'email' => $form->field('email'),
				           'password' => $form->field('password'),
				           'regdate' => time
				         })) {
				$form->field(name => "confirm_password", type => "hidden");
				$form->field(name => "email", type => "hidden");
				$form->text("Registration successful. Now you can Login.");
				print $session->header();
				print misctemplate($form->title, $form->render(submit => ["Login"]));
			}
			else {
				error("Error saving registration.");
			}
		}
		elsif ($form->submitted eq 'Mail Password') {
			my $user_name=$form->field("name");
			my $template=HTML::Template->new(
				filename => "$config{templatedir}/passwordmail.tmpl"
			);
			$template->param(
				user_name => $user_name,
				user_password => userinfo_get($user_name, "password"),
				wikiurl => $config{url},
				wikiname => $config{wikiname},
				REMOTE_ADDR => $ENV{REMOTE_ADDR},
			);
			
			eval q{use Mail::Sendmail};
			my ($fromhost) = $config{cgiurl} =~ m!/([^/]+)!;
			sendmail(
				To => userinfo_get($user_name, "email"),
				From => "$config{wikiname} admin <".(getpwuid($>))[0]."@".$fromhost.">",
				Subject => "$config{wikiname} information",
				Message => $template->output,
			) or error("Failed to send mail");
			
			$form->text("Your password has been emailed to you.");
			$form->field(name => "name", required => 0);
			print $session->header();
			print misctemplate($form->title, $form->render(submit => ["Login", "Register", "Mail Password"]));
		}
	}
	else {
		print $session->header();
		print misctemplate($form->title, $form->render(submit => ["Login", "Register", "Mail Password"]));
	}
} #}}}

sub cgi_prefs ($$) { #{{{
	my $q=shift;
	my $session=shift;

	eval q{use CGI::FormBuilder};
	my $form = CGI::FormBuilder->new(
		title => "preferences",
		fields => [qw(do name password confirm_password email locked_pages)],
		header => 0,
		method => 'POST',
		validate => {
			confirm_password => {
				perl => q{eq $form->field("password")},
			},
			email => 'EMAIL',
		},
		required => 'NONE',
		javascript => 0,
		params => $q,
		action => $q->request_uri,
		template => (-e "$config{templatedir}/prefs.tmpl" ?
		              "$config{templatedir}/prefs.tmpl" : "")
	);
	my @buttons=("Save Preferences", "Logout", "Cancel");
	
	my $user_name=$session->param("name");
	$form->field(name => "do", type => "hidden");
	$form->field(name => "name", disabled => 1,
		value => $user_name, force => 1);
	$form->field(name => "password", type => "password");
	$form->field(name => "confirm_password", type => "password");
	$form->field(name => "locked_pages", size => 50,
		comment => "(".htmllink("", "GlobList", 1).")");
	
	if (! is_admin($user_name)) {
		$form->field(name => "locked_pages", type => "hidden");
	}
	
	if (! $form->submitted) {
		$form->field(name => "email", force => 1,
			value => userinfo_get($user_name, "email"));
		$form->field(name => "locked_pages", force => 1,
			value => userinfo_get($user_name, "locked_pages"));
	}
	
	if ($form->submitted eq 'Logout') {
		$session->delete();
		print $q->redirect($config{url});
		return;
	}
	elsif ($form->submitted eq 'Cancel') {
		print $q->redirect($config{url});
		return;
	}
	elsif ($form->submitted eq "Save Preferences" && $form->validate) {
		foreach my $field (qw(password email locked_pages)) {
			if (length $form->field($field)) {
				userinfo_set($user_name, $field, $form->field($field)) || error("failed to set $field");
			}
		}
		$form->text("Preferences saved.");
	}
	
	print $session->header();
	print misctemplate($form->title, $form->render(submit => \@buttons));
} #}}}

sub cgi_editpage ($$) { #{{{
	my $q=shift;
	my $session=shift;

	eval q{use CGI::FormBuilder};
	my $form = CGI::FormBuilder->new(
		fields => [qw(do rcsinfo subpage from page content comments)],
		header => 1,
		method => 'POST',
		validate => {
			content => '/.+/',
		},
		required => [qw{content}],
		javascript => 0,
		params => $q,
		action => $q->request_uri,
		table => 0,
		template => "$config{templatedir}/editpage.tmpl"
	);
	my @buttons=("Save Page", "Preview", "Cancel");
	
	my ($page)=$form->param('page')=~/$config{wiki_file_regexp}/;
	if (! defined $page || ! length $page || $page ne $q->param('page') ||
	    $page=~/$config{wiki_file_prune_regexp}/ || $page=~/^\//) {
		error("bad page name");
	}
	$page=lc($page);
	
	my $file=$page.$config{default_pageext};
	my $newfile=1;
	if (exists $pagesources{lc($page)}) {
		$file=$pagesources{lc($page)};
		$newfile=0;
	}

	$form->field(name => "do", type => 'hidden');
	$form->field(name => "from", type => 'hidden');
	$form->field(name => "rcsinfo", type => 'hidden');
	$form->field(name => "subpage", type => 'hidden');
	$form->field(name => "page", value => "$page", force => 1);
	$form->field(name => "comments", type => "text", size => 80);
	$form->field(name => "content", type => "textarea", rows => 20,
		cols => 80);
	$form->tmpl_param("can_commit", $config{rcs});
	$form->tmpl_param("indexlink", indexlink());
	$form->tmpl_param("helponformattinglink",
		htmllink("", "HelpOnFormatting", 1));
	if (! $form->submitted) {
		$form->field(name => "rcsinfo", value => rcs_prepedit($file),
			force => 1);
	}
	
	if ($form->submitted eq "Cancel") {
		print $q->redirect("$config{url}/".htmlpage($page));
		return;
	}
	elsif ($form->submitted eq "Preview") {
		require IkiWiki::Render;
		$form->tmpl_param("page_preview",
			htmlize($config{default_pageext},
				linkify($form->field('content'), $page)));
	}
	else {
		$form->tmpl_param("page_preview", "");
	}
	$form->tmpl_param("page_conflict", "");
	
	if (! $form->submitted || $form->submitted eq "Preview" || 
	    ! $form->validate) {
		if ($form->field("do") eq "create") {
			if (exists $pagesources{lc($page)}) {
				# hmm, someone else made the page in the
				# meantime?
				print $q->redirect("$config{url}/".htmlpage($page));
				return;
			}
			
			my @page_locs;
			my $best_loc;
			my ($from)=$form->param('from')=~/$config{wiki_file_regexp}/;
			if (! defined $from || ! length $from ||
			    $from ne $form->param('from') ||
			    $from=~/$config{wiki_file_prune_regexp}/ || $from=~/^\//) {
				@page_locs=$best_loc=$page;
			}
			else {
				my $dir=$from."/";
				$dir=~s![^/]+/$!!;
				
				if (length $form->param('subpage') ||
				    $page eq 'discussion') {
					$best_loc="$from/$page";
				}
				else {
					$best_loc=$dir.$page;
				}
				
				push @page_locs, $dir.$page;
				push @page_locs, "$from/$page";
				while (length $dir) {
					$dir=~s![^/]+/$!!;
					push @page_locs, $dir.$page;
				}

				@page_locs = grep {
					! exists $pagesources{lc($_)} &&
					! page_locked($_, $session, 1)
				} @page_locs;
			}

			$form->tmpl_param("page_select", 1);
			$form->field(name => "page", type => 'select',
				options => \@page_locs, value => $best_loc);
			$form->title("creating ".pagetitle($page));
		}
		elsif ($form->field("do") eq "edit") {
			page_locked($page, $session);
			if (! defined $form->field('content') || 
			    ! length $form->field('content')) {
				my $content="";
				if (exists $pagesources{lc($page)}) {
					$content=readfile("$config{srcdir}/$pagesources{lc($page)}");
					$content=~s/\n/\r\n/g;
				}
				$form->field(name => "content", value => $content,
					force => 1);
			}
			$form->tmpl_param("page_select", 0);
			$form->field(name => "page", type => 'hidden');
			$form->title("editing ".pagetitle($page));
		}
		
		print $form->render(submit => \@buttons);
	}
	else {
		# save page
		page_locked($page, $session);
		
		my $content=$form->field('content');
		$content=~s/\r\n/\n/g;
		$content=~s/\r/\n/g;
		writefile("$config{srcdir}/$file", $content);
		
		my $message="web commit ";
		if (length $session->param("name")) {
			$message.="by ".$session->param("name");
		}
		else {
			$message.="from $ENV{REMOTE_ADDR}";
		}
		if (defined $form->field('comments') &&
		    length $form->field('comments')) {
			$message.=": ".$form->field('comments');
		}
		
		if ($config{rcs}) {
			if ($newfile) {
				rcs_add($file);
			}
			# prevent deadlock with post-commit hook
			unlockwiki();
			# presumably the commit will trigger an update
			# of the wiki
			my $conflict=rcs_commit($file, $message,
				$form->field("rcsinfo"));
		
			if (defined $conflict) {
				$form->field(name => "rcsinfo", value => rcs_prepedit($file),
					force => 1);
				$form->tmpl_param("page_conflict", 1);
				$form->field("content", value => $conflict, force => 1);
				$form->field("do", "edit)");
				$form->tmpl_param("page_select", 0);
				$form->field(name => "page", type => 'hidden');
				$form->title("editing $page");
				print $form->render(submit => \@buttons);
				return;
			}
		}
		else {
			require IkiWiki::Render;
			refresh();
			saveindex();
		}
		
		# The trailing question mark tries to avoid broken
		# caches and get the most recent version of the page.
		print $q->redirect("$config{url}/".htmlpage($page)."?updated");
	}
} #}}}

sub cgi () { #{{{
	eval q{use CGI};
	eval q{use CGI::Session};
	
	my $q=CGI->new;
	
	my $do=$q->param('do');
	if (! defined $do || ! length $do) {
		error("\"do\" parameter missing");
	}
	
	# Things that do not need a session.
	if ($do eq 'recentchanges') {
		cgi_recentchanges($q);
		return;
	}
	
	CGI::Session->name("ikiwiki_session");

	my $oldmask=umask(077);
	my $session = CGI::Session->new("driver:db_file", $q,
		{ FileName => "$config{wikistatedir}/sessions.db" });
	umask($oldmask);
	
	# Everything below this point needs the user to be signed in.
	if ((! $config{anonok} && ! defined $session->param("name") ||
	     ! defined $session->param("name") ||
	     ! userinfo_get($session->param("name"), "regdate")) || $do eq 'signin') {
		cgi_signin($q, $session);
	
		# Force session flush with safe umask.
		my $oldmask=umask(077);
		$session->flush;
		umask($oldmask);
		
		return;
	}
	
	if ($do eq 'create' || $do eq 'edit') {
		cgi_editpage($q, $session);
	}
	elsif ($do eq 'prefs') {
		cgi_prefs($q, $session);
	}
	elsif ($do eq 'blog') {
		# munge page name to be valid, no matter what freeform text
		# is entered
		my $page=lc($q->param('title'));
		$page=~y/ /_/;
		$page=~s/([^-A-Za-z0-9_:+\/])/"__".ord($1)."__"/eg;
		# if the page already exist, munge it to be unique
		my $from=$q->param('from');
		my $add="";
		while (exists $oldpagemtime{"$from/$page$add"}) {
			$add=1 unless length $add;
			$add++;
		}
		$q->param('page', $page.$add);
		# now run same as create
		$q->param('do', 'create');
		cgi_editpage($q, $session);
	}
	else {
		error("unknown do parameter");
	}
} #}}}

1
