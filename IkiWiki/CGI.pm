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

			#translators: The first parameter is a page name,
			#translators: second is the user who locked it.
			error(sprintf(gettext("%s is locked by %s and cannot be edited"),
				htmllink("", "", $page, 1),
				userlink($admin)));
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
	
	# Optimisation: building recentchanges means calculating lots of
	# links. Memoizing htmllink speeds it up a lot (can't be memoized
	# during page builds as the return values may change, but they
	# won't here.)
	eval q{use Memoize};
	error($@) if $@;
	memoize("htmllink");

	eval q{use Time::Duration};
	error($@) if $@;

	my $changelog=[rcs_recentchanges(100)];
	foreach my $change (@$changelog) {
		$change->{when} = concise(ago($change->{when}));

		$change->{user} = userlink($change->{user});

		my $is_excess = exists $change->{pages}[10]; # limit pages to first 10
		delete @{$change->{pages}}[10 .. @{$change->{pages}}] if $is_excess;
		$change->{pages} = [
			map {
				$_->{link} = htmllink("", "", $_->{page}, 1, 0, pagetitle($_->{page}));
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
		header => 1,
		charset => "utf-8",
		method => 'POST',
		required => 'NONE',
		javascript => 0,
		params => $q,
		action => $config{cgiurl},
		header => 0,
		template => scalar template_params("signin.tmpl"),
		stylesheet => baseurl()."style.css",
	);
	my $buttons=["Login"];
	
	$form->field(name => "do", type => "hidden");
	
	if ($q->param("do") ne "signin" && !$form->submitted) {
		$form->text(gettext("You need to log in first."));
	}
	
	run_hooks(formbuilder_setup => sub {
		shift->(form => $form, cgi => $q, session => $session);
	});
	
	decode_form_utf8($form);

	if (exists $hooks{formbuilder}) {
		run_hooks(formbuilder => sub {
			shift->(form => $form, cgi => $q, session => $session,
				buttons => $buttons);
		});
	}
	else {
		if ($form->submitted) {
			$form->validate;
		}
		printheader($session);
		print misctemplate($form->title, $form->render(submit => $buttons));
	}
} #}}}

sub cgi_postsignin ($$) { #{{{
	my $q=shift;
	my $session=shift;

	# Continue with whatever was being done before the signin process.
	if (defined $q->param("do") && $q->param("do") ne "signin" &&
	    defined $session->param("postsignin")) {
		my $postsignin=CGI->new($session->param("postsignin"));
		$session->clear("postsignin");
		cgi($postsignin, $session);
		cgi_savesession($session);
		exit;
	}
	else {
		redirect($q, $config{url});
	}
} #}}}

sub cgi_prefs ($$) { #{{{
	my $q=shift;
	my $session=shift;

	eval q{use CGI::FormBuilder};
	error($@) if $@;
	my $form = CGI::FormBuilder->new(
		title => "preferences",
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
		template => scalar template_params("prefs.tmpl"),
		stylesheet => baseurl()."style.css",
	);
	my $buttons=["Save Preferences", "Logout", "Cancel"];

	run_hooks(formbuilder_setup => sub {
		shift->(form => $form, cgi => $q, session => $session);
	});
	
	$form->field(name => "do", type => "hidden");
	$form->field(name => "email", size => 50);
	$form->field(name => "subscriptions", size => 50,
		comment => "(".htmllink("", "", "PageSpec", 1).")");
	$form->field(name => "locked_pages", size => 50,
		comment => "(".htmllink("", "", "PageSpec", 1).")");
	$form->field(name => "banned_users", size => 50);
	
	my $user_name=$session->param("name");
	if (! is_admin($user_name)) {
		$form->field(name => "locked_pages", type => "hidden");
		$form->field(name => "banned_users", type => "hidden");
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
	elsif ($form->submitted eq 'Save Preferences' && $form->validate) {
		foreach my $field (qw(email subscriptions locked_pages)) {
			if (defined $form->field($field) && length $form->field($field)) {
				userinfo_set($user_name, $field, $form->field($field)) || error("failed to set $field");
			}
		}
		if (is_admin($user_name)) {
			set_banned_users(grep { ! is_admin($_) }
					split(' ', $form->field("banned_users")));
		}
		$form->text(gettext("Preferences saved."));
	}
	
	if (exists $hooks{formbuilder}) {
		run_hooks(formbuilder => sub {
			shift->(form => $form, cgi => $q, session => $session,
				buttons => $buttons);
		});
	}
	else {
		printheader($session);
		print misctemplate($form->title, $form->render(submit => $buttons));
	}
} #}}}

sub cgi_editpage ($$) { #{{{
	my $q=shift;
	my $session=shift;

	my @fields=qw(do rcsinfo subpage from page type editcontent comments);
	my @buttons=("Save Page", "Preview", "Cancel");
	
	eval q{use CGI::FormBuilder};
	error($@) if $@;
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
		template => scalar template_params("editpage.tmpl"),
	);
	
	run_hooks(formbuilder_setup => sub {
		shift->(form => $form, cgi => $q, session => $session);
	});
	
	decode_form_utf8($form);
	
	# This untaint is safe because titlepage removes any problematic
	# characters.
	my ($page)=$form->field('page');
	$page=titlepage(possibly_foolish_untaint($page));
	if (! defined $page || ! length $page || file_pruned($page, $config{srcdir}) || $page=~/^\//) {
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
			}
			push @page_locs, "$config{userdir}/$page"
				if length $config{userdir};

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
			$form->title(sprintf(gettext("creating %s"), pagetitle($page)));
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
			$form->title(sprintf(gettext("editing %s"), pagetitle($page)));
		}
		
		print $form->render(submit => \@buttons);
	}
	else {
		# save page
		page_locked($page, $session);
		
		my $content=$form->field('editcontent');

		$content=~s/\r\n/\n/g;
		$content=~s/\r/\n/g;
		writefile($file, $config{srcdir}, $content);
		
		if ($config{rcs}) {
			my $message="";
			if (defined $form->field('comments') &&
			    length $form->field('comments')) {
				$message=$form->field('comments');
			}
			
			if ($newfile) {
				rcs_add($file);
			}
			# prevent deadlock with post-commit hook
			unlockwiki();
			# presumably the commit will trigger an update
			# of the wiki
			my $conflict=rcs_commit($file, $message,
				$form->field("rcsinfo"),
				$session->param("name"), $ENV{REMOTE_ADDR});
		
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
				$form->title(sprintf(gettext("editing %s"), $page));
				print $form->render(submit => \@buttons);
				return;
			}
			else {
				# Make sure that the repo is up-to-date;
				# locking prevents the post-commit hook
				# from updating it.
				rcs_update();
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
}

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
	
	# Things that do not need a session.
	if ($do eq 'recentchanges') {
		cgi_recentchanges($q);
		return;
	}
	elsif ($do eq 'hyperestraier') {
		cgi_hyperestraier();
	}

	# Need to lock the wiki before getting a session.
	lockwiki();
	
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
				});
			}
		}
	}

	# Everything below this point needs the user to be signed in.
	if (((! $config{anonok} || $do eq 'prefs') &&
	     (! defined $session->param("name") ||
	     ! userinfo_get($session->param("name"), "regdate")))
            || $do eq 'signin') {
	    	if ($do ne 'signin' && ! defined $session->param("postsignin")) {
			$session->param(postsignin => $ENV{QUERY_STRING});
		}
		cgi_signin($q, $session);
		cgi_savesession($session);
		return;
	}
	elsif (defined $session->param("postsignin")) {
		cgi_postsignin($q, $session);
	}

	if (defined $session->param("name") && userinfo_get($session->param("name"), "banned")) {
		print $q->header(-status => "403 Forbidden");
		$session->delete();
		print gettext("You are banned.");
		cgi_savesession($session);
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
		$page=~s/(\/)/"__".ord($1)."__"/eg; # escape slashes too
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
	elsif ($do eq 'postsignin') {
		error(gettext("login failed, perhaps you need to turn on cookies?"));
	}
	else {
		error("unknown do parameter");
	}
} #}}}

sub userlink ($) { #{{{
	my $user=shift;

	eval q{use CGI 'escapeHTML'};
	error($@) if $@;
	if ($user =~ m!^https?://! &&
	    eval q{use Net::OpenID::VerifiedIdentity; 1} && !$@) {
		# Munge user-urls, as used by eg, OpenID.
		my $oid=Net::OpenID::VerifiedIdentity->new(identity => $user);
		my $display=$oid->display;
		# Convert "user.somehost.com" to "user [somehost.com]".
		if ($display !~ /\[/) {
			$display=~s/^(.*?)\.([^.]+\.[a-z]+)$/$1 [$2]/;
		}
		# Convert "http://somehost.com/user" to "user [somehost.com]".
		if ($display !~ /\[/) {
			$display=~s/^https?:\/\/(.+)\/([^\/]+)$/$2 [$1]/;
		}
		$display=~s!^https?://!!; # make sure this is removed
		return "<a href=\"$user\">".escapeHTML($display)."</a>";
	}
	else {
		return htmllink("", "", escapeHTML(
			length $config{userdir} ? $config{userdir}."/".$user : $user
		), 1);
	}
} #}}}

1
