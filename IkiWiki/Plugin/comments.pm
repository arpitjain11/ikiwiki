#!/usr/bin/perl
# Copyright © 2006-2008 Joey Hess <joey@ikiwiki.info>
# Copyright © 2008 Simon McVittie <http://smcv.pseudorandom.co.uk/>
# Licensed under the GNU GPL, version 2, or any later version published by the
# Free Software Foundation
package IkiWiki::Plugin::comments;

use warnings;
use strict;
use IkiWiki 2.00;

use constant PREVIEW => "Preview";
use constant POST_COMMENT => "Post comment";
use constant CANCEL => "Cancel";

sub import { #{{{
	hook(type => "checkconfig", id => 'comments',  call => \&checkconfig);
	hook(type => "getsetup", id => 'comments',  call => \&getsetup);
	hook(type => "preprocess", id => 'comments', call => \&preprocess);
	hook(type => "sessioncgi", id => 'comment', call => \&sessioncgi);
	hook(type => "htmlize", id => "_comment", call => \&htmlize);
	hook(type => "pagetemplate", id => "comments", call => \&pagetemplate);
	IkiWiki::loadplugin("inline");
	IkiWiki::loadplugin("mdwn");
} # }}}

sub htmlize { # {{{
	eval q{use IkiWiki::Plugin::mdwn};
	error($@) if ($@);
	return IkiWiki::Plugin::mdwn::htmlize(@_)
} # }}}

sub getsetup () { #{{{
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
		# Pages where comments are shown, but new comments are not
		# allowed, will show "Comments are closed".
		comments_shown_pagespec => {
			type => 'pagespec',
			example => 'blog/*',
			default => '',
			description => 'PageSpec for pages where comments will be shown inline',
			link => 'ikiwiki/PageSpec',
			safe => 1,
			rebuild => 1,
		},
		comments_open_pagespec => {
			type => 'pagespec',
			example => 'blog/* and created_after(close_old_comments)',
			default => '',
			description => 'PageSpec for pages where new comments can be posted',
			link => 'ikiwiki/PageSpec',
			safe => 1,
			rebuild => 1,
		},
		comments_pagename => {
			type => 'string',
			example => 'comment_',
			default => 'comment_',
			description => 'Base name for comments, e.g. "comment_" for pages like "sandbox/comment_12"',
			safe => 0, # manual page moving will required
			rebuild => undef,
		},
		comments_allowdirectives => {
			type => 'boolean',
			default => 0,
			example => 0,
			description => 'Allow directives in newly posted comments?',
			safe => 1,
			rebuild => 0,
		},
		comments_commit => {
			type => 'boolean',
			example => 1,
			default => 1,
			description => 'commit comments to the VCS',
			# old uncommitted comments are likely to cause
			# confusion if this is changed
			safe => 0,
			rebuild => 0,
		},
} #}}}

sub checkconfig () { #{{{
	$config{comments_commit} = 1 unless defined $config{comments_commit};
	$config{comments_pagename} = 'comment_'
		unless defined $config{comments_pagename};
} #}}}

# Somewhat based on IkiWiki::Plugin::inline blog posting support
sub preprocess (@) { #{{{
	my %params=@_;

	return "";

	my $page = $params{page};
	$pagestate{$page}{comments}{comments} = defined $params{closed}
		? (not IkiWiki::yesno($params{closed}))
		: 1;
	$pagestate{$page}{comments}{allowdirectives} = IkiWiki::yesno($params{allowdirectives});
	$pagestate{$page}{comments}{commit} = defined $params{commit}
		? IkiWiki::yesno($params{commit})
		: 1;

	my $formtemplate = IkiWiki::template("comments_embed.tmpl",
		blind_cache => 1);
	$formtemplate->param(cgiurl => $config{cgiurl});
	$formtemplate->param(page => $params{page});

	if (not $pagestate{$page}{comments}{comments}) {
		$formtemplate->param("disabled" =>
			gettext('comments are closed'));
	}
	elsif ($params{preview}) {
		$formtemplate->param("disabled" =>
			gettext('not available during Preview'));
	}

	debug("page $params{page} => destpage $params{destpage}");

	unless (defined $params{inline} && !IkiWiki::yesno($params{inline})) {
		my $posts = '';
		eval q{use IkiWiki::Plugin::inline};
		error($@) if ($@);
		my @args = (
			pages => "internal($params{page}/_comment_*)",
			template => "comments_display",
			show => 0,
			reverse => "yes",
			# special stuff passed through
			page => $params{page},
			destpage => $params{destpage},
			preview => $params{preview},
		);
		push @args, atom => $params{atom} if defined $params{atom};
		push @args, rss => $params{rss} if defined $params{rss};
		push @args, feeds => $params{feeds} if defined $params{feeds};
		push @args, feedshow => $params{feedshow} if defined $params{feedshow};
		push @args, timeformat => $params{timeformat} if defined $params{timeformat};
		push @args, feedonly => $params{feedonly} if defined $params{feedonly};
		$posts = IkiWiki::preprocess_inline(@args);
		$formtemplate->param("comments" => $posts);
	}

	return $formtemplate->output;
} # }}}

# FIXME: logic taken from editpage, should be common code?
sub getcgiuser ($) { # {{{
	my $session = shift;
	my $user = $session->param('name');
	$user = $ENV{REMOTE_ADDR} unless defined $user;
	debug("getcgiuser() -> $user");
	return $user;
} # }}}

# FIXME: logic adapted from recentchanges, should be common code?
# returns (author URL, pretty-printed version)
sub linkuser ($) { # {{{
	my $user = shift;
	my $oiduser = eval { IkiWiki::openiduser($user) };

	if (defined $oiduser) {
		return ($user, $oiduser);
	}
	else {
		my $page = bestlink('', (length $config{userdir}
				? "$config{userdir}/"
				: "").$user);
		return (urlto($page, undef, 1), $user);
	}
} # }}}

# Mostly cargo-culted from IkiWiki::plugin::editpage
sub sessioncgi ($$) { #{{{
	my $cgi=shift;
	my $session=shift;

	my $do = $cgi->param('do');
	return unless $do eq 'comment';

	IkiWiki::decode_cgi_utf8($cgi);

	eval q{use CGI::FormBuilder};
	error($@) if $@;

	my @buttons = (POST_COMMENT, PREVIEW, CANCEL);
	my $form = CGI::FormBuilder->new(
		fields => [qw{do sid page subject body}],
		charset => 'utf-8',
		method => 'POST',
		required => [qw{body}],
		javascript => 0,
		params => $cgi,
		action => $config{cgiurl},
		header => 0,
		table => 0,
		template => scalar IkiWiki::template_params('comments_form.tmpl'),
		# wtf does this do in editpage?
		wikiname => $config{wikiname},
	);

	IkiWiki::decode_form_utf8($form);
	IkiWiki::run_hooks(formbuilder_setup => sub {
			shift->(title => "comment", form => $form, cgi => $cgi,
				session => $session, buttons => \@buttons);
		});
	IkiWiki::decode_form_utf8($form);

	$form->field(name => 'do', type => 'hidden');
	$form->field(name => 'sid', type => 'hidden', value => $session->id,
		force => 1);
	$form->field(name => 'page', type => 'hidden');
	$form->field(name => 'subject', type => 'text', size => 72);
	$form->field(name => 'body', type => 'textarea', rows => 5,
		cols => 80);

	# The untaint is OK (as in editpage) because we're about to pass
	# it to file_pruned anyway
	my $page = $form->field('page');
	$page = IkiWiki::possibly_foolish_untaint($page);
	if (!defined $page || !length $page ||
		IkiWiki::file_pruned($page, $config{srcdir})) {
		error(gettext("bad page name"));
	}

	my $allow_directives = $config{comments_allowdirectives};
	my $commit_comments = $config{comments_commit};
	my $comments_pagename = $config{comments_pagename};

	# FIXME: is this right? Or should we be using the candidate subpage
	# (whatever that might mean) as the base URL?
	my $baseurl = urlto($page, undef, 1);

	$form->title(sprintf(gettext("commenting on %s"),
			IkiWiki::pagetitle($page)));

	$form->tmpl_param('helponformattinglink',
		htmllink($page, $page, 'ikiwiki/formatting',
			noimageinline => 1,
			linktext => 'FormattingHelp'),
			allowdirectives => $allow_directives);

	if ($form->submitted eq CANCEL) {
		# bounce back to the page they wanted to comment on, and exit.
		# CANCEL need not be considered in future
		IkiWiki::redirect($cgi, urlto($page, undef, 1));
		exit;
	}

	if (not exists $pagesources{$page}) {
		error(sprintf(gettext(
			"page '%s' doesn't exist, so you can't comment"),
			$page));
	}

	if (not pagespec_match($page, $config{comments_open_pagespec},
		location => $page)) {
		error(sprintf(gettext(
			"comments on page '%s' are closed"),
			$page));
	}

	IkiWiki::check_canedit($page . "[postcomment]", $cgi, $session);

	my ($authorurl, $author) = linkuser(getcgiuser($session));

	my $body = $form->field('body') || '';
	$body =~ s/\r\n/\n/g;
	$body =~ s/\r/\n/g;
	$body .= "\n" if $body !~ /\n$/;

	unless ($allow_directives) {
		# don't allow new-style directives at all
		$body =~ s/(^|[^\\])\[\[!/$1&#91;&#91;!/g;

		# don't allow [[ unless it begins an old-style
		# wikilink, if prefix_directives is off
		$body =~ s/(^|[^\\])\[\[(?![^\n\s\]+]\]\])/$1&#91;&#91;!/g
			unless $config{prefix_directives};
	}

	# FIXME: check that the wiki is locked right now, because
	# if it's not, there are mad race conditions!

	# FIXME: rather a simplistic way to make the comments...
	my $i = 0;
	my $file;
	my $location;
	do {
		$i++;
		$location = "$page/${comments_pagename}${i}";
	} while (-e "$config{srcdir}/$location._comment");

	my $anchor = "${comments_pagename}${i}";

	IkiWiki::run_hooks(sanitize => sub {
		$body=shift->(
			page => $location,
			destpage => $location,
			content => $body,
		);
	});

	# In this template, the [[!meta]] directives should stay at the end,
	# so that they will override anything the user specifies. (For
	# instance, [[!meta author="I can fake the author"]]...)
	my $content_tmpl = template('comments_comment.tmpl');
	$content_tmpl->param(author => $author);
	$content_tmpl->param(authorurl => $authorurl);
	$content_tmpl->param(subject => $form->field('subject'));
	$content_tmpl->param(body => $body);
	$content_tmpl->param(anchor => "$anchor");
	$content_tmpl->param(permalink => "$baseurl#$anchor");
	$content_tmpl->param(date => IkiWiki::formattime(time, "%X %x"));

	my $content = $content_tmpl->output;

	# This is essentially a simplified version of editpage:
	# - the user does not control the page that's created, only the parent
	# - it's always a create operation, never an edit
	# - this means that conflicts should never happen
	# - this means that if they do, rocks fall and everyone dies

	if ($form->submitted eq PREVIEW) {
		my $preview = IkiWiki::htmlize($location, $page, 'mdwn',
				IkiWiki::linkify($page, $page,
					IkiWiki::preprocess($page, $page,
						IkiWiki::filter($location,
							$page, $content),
						0, 1)));
		IkiWiki::run_hooks(format => sub {
				$preview = shift->(page => $page,
					content => $preview);
			});

		my $template = template("comments_display.tmpl");
		$template->param(content => $preview);
		$template->param(title => $form->field('subject'));
		$template->param(ctime => displaytime(time));
		$template->param(author => $author);
		$template->param(authorurl => $authorurl);

		$form->tmpl_param(page_preview => $template->output);
	}
	else {
		$form->tmpl_param(page_preview => "");
	}

	if ($form->submitted eq POST_COMMENT && $form->validate) {
		my $file = "$location._comment";

		IkiWiki::checksessionexpiry($session, $cgi->param('sid'));

		# FIXME: could probably do some sort of graceful retry
		# on error? Would require significant unwinding though
		writefile($file, $config{srcdir}, $content);

		my $conflict;

		if ($config{rcs} and $commit_comments) {
			my $message = gettext("Added a comment");
			if (defined $form->field('subject') &&
				length $form->field('subject')) {
				$message = sprintf(
					gettext("Added a comment: %s"),
					$form->field('subject'));
			}

			IkiWiki::rcs_add($file);
			IkiWiki::disable_commit_hook();
			$conflict = IkiWiki::rcs_commit_staged($message,
				$session->param('name'), $ENV{REMOTE_ADDR});
			IkiWiki::enable_commit_hook();
			IkiWiki::rcs_update();
		}

		# Now we need a refresh
		require IkiWiki::Render;
		IkiWiki::refresh();
		IkiWiki::saveindex();

		# this should never happen, unless a committer deliberately
		# breaks it or something
		error($conflict) if defined $conflict;

		# Bounce back to where we were, but defeat broken caches
		my $anticache = "?updated=$page/${comments_pagename}${i}";
		IkiWiki::redirect($cgi, urlto($page, undef, 1).$anticache);
	}
	else {
		IkiWiki::showform ($form, \@buttons, $session, $cgi,
			forcebaseurl => $baseurl);
	}

	exit;
} #}}}

sub pagetemplate (@) { #{{{
	my %params = @_;

	my $page = $params{page};
	my $template = $params{template};

	if ($template->query(name => 'comments')) {
		my $comments = undef;

		my $comments_pagename = $config{comments_pagename};

		my $open = 0;
		my $shown = pagespec_match($page,
			$config{comments_shown_pagespec},
			location => $page);

		if (pagespec_match($page, "*/${comments_pagename}*",
				location => $page)) {
			$shown = 0;
			$open = 0;
		}

		if (length $config{cgiurl}) {
			$open = pagespec_match($page,
				$config{comments_open_pagespec},
				location => $page);
		}

		if ($shown) {
			eval q{use IkiWiki::Plugin::inline};
			error($@) if $@;

			my @args = (
				pages => "internal($page/${comments_pagename}*)",
				template => 'comments_display',
				show => 0,
				reverse => 'yes',
				page => $page,
				destpage => $params{destpage},
			);
			$comments = IkiWiki::preprocess_inline(@args);
		}

		if (defined $comments && length $comments) {
			$template->param(comments => $comments);
		}

		if ($open) {
			my $commenturl = IkiWiki::cgiurl(do => 'comment',
				page => $page);
			$template->param(commenturl => $commenturl);
		}
	}
} # }}}

package IkiWiki::PageSpec;

sub match_postcomment ($$;@) {
	my $page = shift;
	my $glob = shift;

	unless ($page =~ s/\[postcomment\]$//) {
		return IkiWiki::FailReason->new("not posting a comment");
	}
	return match_glob($page, $glob);
}

1
