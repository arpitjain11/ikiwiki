#!/usr/bin/perl
# Copyright © 2006-2008 Joey Hess <joey@ikiwiki.info>
# Copyright © 2008 Simon McVittie <http://smcv.pseudorandom.co.uk/>
# Licensed under the GNU GPL, version 2, or any later version published by the
# Free Software Foundation
package IkiWiki::Plugin::comments;

use warnings;
use strict;
use IkiWiki 2.00;
use Encode;

use constant PREVIEW => "Preview";
use constant POST_COMMENT => "Post comment";
use constant CANCEL => "Cancel";

sub import { #{{{
	hook(type => "checkconfig", id => 'comments',  call => \&checkconfig);
	hook(type => "getsetup", id => 'comments',  call => \&getsetup);
	hook(type => "preprocess", id => 'comment', call => \&preprocess);
	hook(type => "sessioncgi", id => 'comment', call => \&sessioncgi);
	hook(type => "htmlize", id => "_comment", call => \&htmlize);
	hook(type => "pagetemplate", id => "comments", call => \&pagetemplate);
	hook(type => "cgi", id => "comments", call => \&linkcgi);
	IkiWiki::loadplugin("mdwn");
	IkiWiki::loadplugin("inline");
} # }}}

sub htmlize { # {{{
	my %params = @_;
	return $params{content};
} # }}}

sub preprocess { # {{{
	my %params = @_;
	my $page = $params{page};

	my $format = $params{format};
	if (defined $format && !exists $IkiWiki::hooks{htmlize}{$format}) {
		error(sprintf(gettext("unsupported page format %s"), $format));
	}

	my $content = $params{content};
	if (!defined $content) {
		error(gettext("comment must have content"));
	}
	$content =~ s/\\"/"/g;

	$content = IkiWiki::filter($page, $params{destpage}, $content);

	if ($config{comments_allowdirectives}) {
		$content = IkiWiki::preprocess($page, $params{destpage},
			$content);
	}

	# no need to bother with htmlize if it's just HTML
	$content = IkiWiki::htmlize($page, $params{destpage}, $format,
		$content) if defined $format;

	IkiWiki::run_hooks(sanitize => sub {
		$content = shift->(
			page => $page,
			destpage => $params{destpage},
			content => $content,
		);
	});

	# override any metadata

	if (defined $params{username}) {
		my ($authorurl, $author) = linkuser($params{username});
		$pagestate{$page}{meta}{author} = $author;
		$pagestate{$page}{meta}{authorurl} = $authorurl;
	}
	elsif (defined $params{ip}) {
		$pagestate{$page}{meta}{author} = sprintf(
			gettext("Anonymous (IP: %s)"),
			$params{ip});
		delete $pagestate{$page}{meta}{authorurl};
	}
	else {
		$pagestate{$page}{meta}{author} = gettext("Anonymous");
		delete $pagestate{$page}{meta}{authorurl};
	}

	if (defined $params{subject}) {
		$pagestate{$page}{meta}{title} = $params{subject};
	}
	else {
		delete $pagestate{$page}{meta}{title};
	}

	my $baseurl = urlto($params{destpage}, undef, 1);
	my $anchor = "";
	my $comments_pagename = $config{comments_pagename};
	if ($params{page} =~ m/\/(\Q${comments_pagename}\E\d+)$/) {
		$anchor = $1;
	}
	$pagestate{$page}{meta}{permalink} = "${baseurl}#${anchor}";

	eval q{use Date::Parse};
	if (! $@) {
		my $time = str2time($params{date});
		$IkiWiki::pagectime{$page} = $time if defined $time;
	}

	# FIXME: hard-coded HTML (although it's just to set an ID)
	return "<div id=\"$anchor\">$content</div>" if $anchor;
	return $content;
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

# FIXME: logic taken from editpage, should be common code?
sub getcgiuser ($) { # {{{
	my $session = shift;
	my $user = $session->param('name');
	$user = $ENV{REMOTE_ADDR} unless defined $user;
	debug("getcgiuser() -> $user");
	return $user;
} # }}}

# This is exactly the same as recentchanges_link :-(
sub linkcgi ($) { #{{{
	my $cgi=shift;
	if (defined $cgi->param('do') && $cgi->param('do') eq "commenter") {

		my $page=decode_utf8($cgi->param("page"));
		if (!defined $page) {
			error("missing page parameter");
		}

		IkiWiki::loadindex();

		my $link=bestlink("", $page);
		if (! length $link) {
			print "Content-type: text/html\n\n";
			print IkiWiki::misctemplate(gettext(gettext("missing page")),
				"<p>".
				sprintf(gettext("The page %s does not exist."),
					htmllink("", "", $page)).
				"</p>");
		}
		else {
			IkiWiki::redirect($cgi, urlto($link, undef, 1));
		}

		exit;
	}
}

# FIXME: basically the same logic as recentchanges
# returns (author URL, pretty-printed version)
sub linkuser ($) { # {{{
	my $user = shift;
	my $oiduser = eval { IkiWiki::openiduser($user) };

	if (defined $oiduser) {
		return ($user, $oiduser);
	}
	# FIXME: it'd be good to avoid having such a link for anonymous
	# posts
	else {
		return (IkiWiki::cgiurl(
				do => 'commenter',
				page => (length $config{userdir}
					? "$config{userdir}/$user"
					: "$user")
			), $user);
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

	$body =~ s/"/\\"/g;
	my $content = "[[!comment format=mdwn\n";

	# FIXME: handling of double quotes probably wrong?
	if (defined $session->param('name')) {
		my $username = $session->param('name');
		$username =~ s/"/&quot;/g;
		$content .= " username=\"$username\"\n";
	}
	elsif (defined $ENV{REMOTE_ADDR}) {
		my $ip = $ENV{REMOTE_ADDR};
		if ($ip =~ m/^([.0-9]+)$/) {
			$content .= " ip=\"$1\"\n";
		}
	}

	my $subject = $form->field('subject');
	$subject =~ s/"/&quot;/g;
	$content .= " subject=\"$subject\"\n";

	$content .= " date=\"" . IkiWiki::formattime(time, '%X %x') . "\"\n";

	$content .= " content=\"\"\"\n$body\n\"\"\"]]\n";

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
