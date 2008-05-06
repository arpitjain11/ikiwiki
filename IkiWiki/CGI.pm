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

sub page_locked ($$;$) { #{{{
	my $page=shift;
	my $session=shift;
	my $nonfatal=shift;
	
	my $user=$session->param("name");
	return if defined $user && is_admin($user);

	foreach my $admin (@{$config{adminuser}}) {
		my $locked_pages=userinfo_get($admin, "locked_pages");
		if (pagespec_match($page, userinfo_get($admin, "locked_pages"))) {
			return 1 if $nonfatal;
			error(htmllink("", "", $page, 1)." is locked by ".
			      htmllink("", "", $admin, 1)." and cannot be edited.");
		}
	}

	return 0;
} #}}}

sub decode_form_utf8 ($) { #{{{
	my $form = shift;
	foreach my $f ($form->field) {
		next if Encode::is_utf8(scalar $form->field($f));
		$form->field(name  => $f,
			     value => decode_utf8($form->field($f)),
			     force => 1,
			    );
	}
} #}}}

sub cgi_recentchanges ($) { #{{{
	my $q=shift;
	
	unlockwiki();

	# Optimisation: building recentchanges means calculating lots of
	# links. Memoizing htmllink speeds it up a lot (can't be memoized
	# during page builds as the return values may change, but they
	# won't here.)
	eval q{use Memoize};
	error($@) if $@;
	memoize("htmllink");

	eval q{use Time::Duration};
	error($@) if $@;
	eval q{use CGI 'escapeHTML'};
	error($@) if $@;

	my $changelog=[rcs_recentchanges(100)];
	foreach my $change (@$changelog) {
		$change->{when} = concise(ago($change->{when}));
		$change->{user} = htmllink("", "", escapeHTML($change->{user}), 1);

		my $is_excess = exists $change->{pages}[10]; # limit pages to first 10
		delete @{$change->{pages}}[10 .. @{$change->{pages}}] if $is_excess;
		$change->{pages} = [
			map {
				$_->{link} = htmllink("", "", $_->{page}, 1);
				$_;
			} @{$change->{pages}}
		];
		push @{$change->{pages}}, { link => '...' } if $is_excess;
	}

	my $template=template("recentchanges.tmpl"); 
	$template->param(
		title => "RecentChanges",
		indexlink => indexlink(),
		wikiname => $config{wikiname},
		changelog => $changelog,
		baseurl => baseurl(),
	);
	run_hooks(pagetemplate => sub {
		shift->(page => "", destpage => "", template => $template);
	});
	print $q->header(-charset => 'utf-8'), $template->output;
} #}}}

sub cgi_signin ($$) { #{{{
	my $q=shift;
	my $session=shift;

	eval q{use CGI::FormBuilder};
	error($@) if $@;
	my $form = CGI::FormBuilder->new(
		title => "signin",
		fields => [qw(do title page subpage from name password)],
		header => 1,
		charset => "utf-8",
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
		action => $config{cgiurl},
		header => 0,
		template => (-e "$config{templatedir}/signin.tmpl" ?
			     {template_params("signin.tmpl")} : ""),
		stylesheet => baseurl()."style.css",
	);
		
	decode_form_utf8($form);
	
	$form->field(name => "name", required => 0);
	$form->field(name => "do", type => "hidden");
	$form->field(name => "page", type => "hidden");
	$form->field(name => "title", type => "hidden");
	$form->field(name => "from", type => "hidden");
	$form->field(name => "subpage", type => "hidden");
	$form->field(name => "password", type => "password", required => 0);
	if ($form->submitted eq "Register" || $form->submitted eq "Create Account") {
		$form->title("register");
		$form->text("");
		$form->fields(qw(do title page subpage from name password confirm_password email));
		$form->field(name => "confirm_password", type => "password");
		$form->field(name => "email", type => "text");
	}
	if ($q->param("do") ne "signin" && !$form->submitted) {
		$form->text("You need to log in first.");
	}
	
	if ($form->submitted) {
		# Set required fields based on how form was submitted.
		my %required=(
			"Login" => [qw(name password)],
			"Register" => [],
			"Create Account" => [qw(name password confirm_password email)],
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
		if ($form->submitted eq 'Create Account' ||
		    $form->submitted eq 'Register') {
			$form->field(
				name => "name",
				validate => sub {
					my $name=shift;
					length $name &&
					$name=~/$config{wiki_file_regexp}/ &&
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
		if ($session->param("name")) {
			$form->field(name => "name", value => $session->param("name"));
		}
	}

	if ($form->submitted && $form->validate) {
		if ($form->submitted eq 'Login') {
			$session->param("name", $form->field("name"));
			if (defined $form->field("do") && 
			    $form->field("do") ne 'signin') {
				redirect($q, cgiurl(
					do => $form->field("do"),
					page => $form->field("page"),
					title => $form->field("title"),
					subpage => $form->field("subpage"),
					from => $form->field("from"),
				));
			}
			else {
				redirect($q, $config{url});
			}
		}
		elsif ($form->submitted eq 'Create Account') {
			my $user_name=$form->field('name');
			if (userinfo_setall($user_name, {
				           'email' => $form->field('email'),
				           'password' => $form->field('password'),
				           'regdate' => time
				         })) {
				$form->field(name => "confirm_password", type => "hidden");
				$form->field(name => "email", type => "hidden");
				$form->text("Account creation successful. Now you can Login.");
				printheader($session);
				print misctemplate($form->title, $form->render(submit => ["Login"]));
			}
			else {
				error("Error creating account.");
			}
		}
		elsif ($form->submitted eq 'Mail Password') {
			my $user_name=$form->field("name");
			my $template=template("passwordmail.tmpl");
			$template->param(
				user_name => $user_name,
				user_password => userinfo_get($user_name, "password"),
				wikiurl => $config{url},
				wikiname => $config{wikiname},
				REMOTE_ADDR => $ENV{REMOTE_ADDR},
			);
			
			eval q{use Mail::Sendmail};
			error($@) if $@;
			sendmail(
				To => userinfo_get($user_name, "email"),
				From => "$config{wikiname} admin <$config{adminemail}>",
				Subject => "$config{wikiname} information",
				Message => $template->output,
			) or error("Failed to send mail");
			
			$form->text("Your password has been emailed to you.");
			$form->field(name => "name", required => 0);
			printheader($session);
			print misctemplate($form->title, $form->render(submit => ["Login", "Mail Password"]));
		}
		elsif ($form->submitted eq "Register") {
			printheader($session);
			print misctemplate($form->title, $form->render(submit => ["Create Account"]));
		}
	}
	elsif ($form->submitted eq "Create Account") {
		printheader($session);
		print misctemplate($form->title, $form->render(submit => ["Create Account"]));
	}
	else {
		printheader($session);
		print misctemplate($form->title, $form->render(submit => ["Login", "Register", "Mail Password"]));
	}
} #}}}

sub cgi_prefs ($$) { #{{{
	my $q=shift;
	my $session=shift;

	# The session id is stored on the form and checked to
	# guard against CSRF.
	my $sid=$q->param('sid');
	if (! defined $sid) {
		$q->delete_all;
	}
	elsif ($sid ne $session->id) {
		error("Your login session has expired.");
	}

	eval q{use CGI::FormBuilder};
	error($@) if $@;
	my $form = CGI::FormBuilder->new(
		title => "preferences",
		fields => [qw(do name password confirm_password email 
		              subscriptions locked_pages)],
		header => 0,
		charset => "utf-8",
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
		action => $config{cgiurl},
		template => (-e "$config{templatedir}/prefs.tmpl" ?
			     {template_params("prefs.tmpl")} : ""),
		stylesheet => baseurl()."style.css",
	);
	my @buttons=("Save Preferences", "Logout", "Cancel");
	
	my $user_name=$session->param("name");
	$form->field(name => "do", type => "hidden", value => "prefs",
		force => 1);
	$form->field(name => "sid", type => "hidden", value => $session->id,
		force => 1);
	$form->field(name => "name", disabled => 1,
		value => $user_name, force => 1);
	$form->field(name => "password", type => "password");
	$form->field(name => "confirm_password", type => "password");
	$form->field(name => "subscriptions", size => 50,
		comment => "(".htmllink("", "", "PageSpec", 1).")");
	$form->field(name => "locked_pages", size => 50,
		comment => "(".htmllink("", "", "PageSpec", 1).")");
	$form->field(name => "banned_users", size => 50);
	
	if (! is_admin($user_name)) {
		$form->field(name => "locked_pages", type => "hidden");
		$form->field(name => "banned_users", type => "hidden");
	}

	if ($config{httpauth}) {
		$form->field(name => "password", type => "hidden");
		$form->field(name => "confirm_password", type => "hidden");
	}
	
	if (! $form->submitted) {
		$form->field(name => "email", force => 1,
			value => userinfo_get($user_name, "email"));
		$form->field(name => "subscriptions", force => 1,
			value => userinfo_get($user_name, "subscriptions"));
		$form->field(name => "locked_pages", force => 1,
			value => userinfo_get($user_name, "locked_pages"));
		if (is_admin($user_name)) {
			$form->field(name => "banned_users", force => 1,
				value => join(" ", get_banned_users()));
		}
	}
	
	decode_form_utf8($form);
	
	if ($form->submitted eq 'Logout') {
		$session->delete();
		redirect($q, $config{url});
		return;
	}
	elsif ($form->submitted eq 'Cancel') {
		redirect($q, $config{url});
		return;
	}
	elsif ($form->submitted eq "Save Preferences" && $form->validate) {
		foreach my $field (qw(password email subscriptions locked_pages)) {
			if (length $form->field($field)) {
				userinfo_set($user_name, $field, $form->field($field)) || error("failed to set $field");
			}
		}
		if (is_admin($user_name)) {
			set_banned_users(grep { ! is_admin($_) }
					split(' ', $form->field("banned_users")));
		}
		$form->text("Preferences saved.");
	}
	
	printheader($session);
	print misctemplate($form->title, $form->render(submit => \@buttons));
} #}}}

sub cgi_editpage ($$) { #{{{
	my $q=shift;
	my $session=shift;

	my @fields=qw(do rcsinfo subpage from page type editcontent comments);
	my @buttons=("Save Page", "Preview", "Cancel");
	
	eval q{use CGI::FormBuilder; use CGI::FormBuilder::Template::HTML};
	error($@) if $@;
	my $renderer=CGI::FormBuilder::Template::HTML->new(
		fields => \@fields,
		template_params("editpage.tmpl"),
	);
	run_hooks(pagetemplate => sub {
		shift->(page => "", destpage => "", template => $renderer->engine);
	});
	my $form = CGI::FormBuilder->new(
		fields => \@fields,
		header => 1,
		charset => "utf-8",
		method => 'POST',
		validate => {
			editcontent => '/.+/',
		},
		required => [qw{editcontent}],
		javascript => 0,
		params => $q,
		action => $config{cgiurl},
		table => 0,
		template => $renderer,
	);
	
	decode_form_utf8($form);
	
	# This untaint is safe because titlepage removes any problematic
	# characters.
	my ($page)=$form->field('page');
	$page=titlepage(possibly_foolish_untaint($page));
	if (! defined $page || ! length $page ||
	    $page=~/$config{wiki_file_prune_regexp}/ || $page=~/^\//) {
		error("bad page name");
	}
	
	my $from;
	if (defined $form->field('from')) {
		($from)=$form->field('from')=~/$config{wiki_file_regexp}/;
	}
	
	my $file;
	my $type;
	if (exists $pagesources{$page}) {
		$file=$pagesources{$page};
		$type=pagetype($file);
		if (! defined $type) {
			error("$page is not an editable page");
		}
	}
	else {
		$type=$form->param('type');
		if (defined $type && length $type && $hooks{htmlize}{$type}) {
			$type=possibly_foolish_untaint($type);
		}
		elsif (defined $from) {
			# favor the type of linking page
			$type=pagetype($pagesources{$from});
		}
		$type=$config{default_pageext} unless defined $type;
		$file=$page.".".$type;
	}

	my $newfile=0;
	if (! -e "$config{srcdir}/$file") {
		$newfile=1;
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
		htmllink("", "", "HelpOnFormatting", 1));
	$form->tmpl_param("baseurl", baseurl());
	if (! $form->submitted) {
		$form->field(name => "rcsinfo", value => rcs_prepedit($file),
			force => 1);
	}
	
	if ($form->submitted eq "Cancel") {
		if ($newfile && defined $from) {
			redirect($q, "$config{url}/".htmlpage($from));
		}
		elsif ($newfile) {
			redirect($q, $config{url});
		}
		else {
			redirect($q, "$config{url}/".htmlpage($page));
		}
		return;
	}
	elsif ($form->submitted eq "Preview") {
		my $content=$form->field('editcontent');
		my $comments=$form->field('comments');
		$form->field(name => "editcontent",
				value => $content, force => 1);
		$form->field(name => "comments",
				value => $comments, force => 1);
		$config{rss}=$config{atom}=0; # avoid preview writing a feed!
		$form->tmpl_param("page_preview",
			htmlize($page, $type,
			linkify($page, "",
			preprocess($page, $page,
			filter($page, $content)))));
	}
	else {
		$form->tmpl_param("page_preview", "");
	}
	$form->tmpl_param("page_conflict", "");
	
	if (! $form->submitted || $form->submitted eq "Preview" || 
	    ! $form->validate) {
		if ($form->field("do") eq "create") {
			my @page_locs;
			my $best_loc;
			if (! defined $from || ! length $from ||
			    $from ne $form->field('from') ||
			    $from=~/$config{wiki_file_prune_regexp}/ ||
			    $from=~/^\// ||
			    $form->submitted eq "Preview") {
				@page_locs=$best_loc=$page;
			}
			else {
				my $dir=$from."/";
				$dir=~s![^/]+/+$!!;
				
				if ((defined $form->field('subpage') && length $form->field('subpage')) ||
				    $page eq 'discussion') {
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
			}

			@page_locs = grep {
				! exists $pagecase{lc $_} &&
				! page_locked($_, $session, 1)
			} @page_locs;
			
			if (! @page_locs) {
				# hmm, someone else made the page in the
				# meantime?
				redirect($q, "$config{url}/".htmlpage($page));
				return;
			}
			
			my @page_types;
			if (exists $hooks{htmlize}) {
				@page_types=keys %{$hooks{htmlize}};
			}
			
			$form->tmpl_param("page_select", 1);
			$form->field(name => "page", type => 'select',
				options => \@page_locs, value => $best_loc);
			$form->field(name => "type", type => 'select',
				options => \@page_types);
			$form->title("creating ".pagetitle($page));
		}
		elsif ($form->field("do") eq "edit") {
			page_locked($page, $session);
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
			$form->title("editing ".pagetitle($page));
		}
		
		print $form->render(submit => \@buttons);
	}
	else {
		# save page
		page_locked($page, $session);
		
		# The session id is stored on the form and checked to
		# guard against CSRF. But only if the user is logged in,
		# as anonok can allow anonymous edits.
		if (defined $session->param("name")) {
			my $sid=$q->param('sid');
			if (! defined $sid || $sid ne $session->id) {
				error("Your login session has expired.");
			}
		}

		my $content=$form->field('editcontent');

		$content=~s/\r\n/\n/g;
		$content=~s/\r/\n/g;
		writefile($file, $config{srcdir}, $content);
		
		my $message="web commit ";
		if (defined $session->param("name") && 
		    length $session->param("name")) {
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
				$form->field("editcontent", value => $conflict, force => 1);
				$form->field(name => "comments", value => $form->field('comments'), force => 1);
				$form->field("do", "edit)");
				$form->tmpl_param("page_select", 0);
				$form->field(name => "page", type => 'hidden');
				$form->field(name => "type", type => 'hidden');
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
		redirect($q, "$config{url}/".htmlpage($page)."?updated");
	}
} #}}}

sub cgi () { #{{{
	eval q{use CGI; use CGI::Session};
	error($@) if $@;
	
	my $q=CGI->new;
	
	run_hooks(cgi => sub { shift->($q) });
	
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
	
	# Things that do not need a session.
	if ($do eq 'recentchanges') {
		cgi_recentchanges($q);
		return;
	}
	elsif ($do eq 'hyperestraier') {
		cgi_hyperestraier();
	}
	
	CGI::Session->name("ikiwiki_session_".encode_utf8($config{wikiname}));
	
	my $oldmask=umask(077);
	my $session = CGI::Session->new("driver:DB_File", $q,
		{ FileName => "$config{wikistatedir}/sessions.db" });
	umask($oldmask);
	
	# Everything below this point needs the user to be signed in.
	if (((! $config{anonok} || $do eq 'prefs') &&
	     (! $config{httpauth}) &&
	     (! defined $session->param("name") ||
	     ! userinfo_get($session->param("name"), "regdate"))) || $do eq 'signin') {
		cgi_signin($q, $session);
	
		# Force session flush with safe umask.
		my $oldmask=umask(077);
		$session->flush;
		umask($oldmask);
		
		return;
	}

	if ($config{httpauth} && (! defined $session->param("name"))) {
		if (! defined $q->remote_user()) {
			error("Could not determine authenticated username.");
		}
		else {
			$session->param("name", $q->remote_user());
			if (! userinfo_get($session->param("name"), "regdate")) {
				userinfo_setall($session->param("name"), {
					email => "",
					password => "",
					regdate=>time,
				});
			}
		}
	}

	if (defined $session->param("name") && userinfo_get($session->param("name"), "banned")) {
		print $q->header(-status => "403 Forbidden");
		$session->delete();
		print "You are banned.";
		exit;
	}
	
	if ($do eq 'create' || $do eq 'edit') {
		cgi_editpage($q, $session);
	}
	elsif ($do eq 'prefs') {
		cgi_prefs($q, $session);
	}
	elsif ($do eq 'blog') {
		my $page=titlepage(decode_utf8($q->param('title')));
		# if the page already exists, munge it to be unique
		my $from=$q->param('from');
		my $add="";
		while (exists $pagecase{lc "$from/$page$add"}) {
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
