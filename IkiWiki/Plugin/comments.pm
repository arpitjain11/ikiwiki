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
use POSIX qw(strftime);

use constant PREVIEW => "Preview";
use constant POST_COMMENT => "Post comment";
use constant CANCEL => "Cancel";

my $postcomment;

sub import { #{{{
	hook(type => "checkconfig", id => 'comments',  call => \&checkconfig);
	hook(type => "getsetup", id => 'comments',  call => \&getsetup);
	hook(type => "preprocess", id => '_comment', call => \&preprocess);
	hook(type => "sessioncgi", id => 'comment', call => \&sessioncgi);
	hook(type => "htmlize", id => "_comment", call => \&htmlize);
	hook(type => "pagetemplate", id => "comments", call => \&pagetemplate);
	hook(type => "cgi", id => "comments", call => \&linkcgi);
	IkiWiki::loadplugin("inline");
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
			safe => 0, # manual page moving required
			rebuild => undef,
		},
		comments_allowdirectives => {
			type => 'boolean',
			default => 0,
			example => 0,
			description => 'Interpret directives in comments?',
			safe => 1,
			rebuild => 0,
		},
		comments_allowauthor => {
			type => 'boolean',
			default => 0,
			example => 0,
			description => 'Allow anonymous commenters to set an author name?',
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

sub htmlize { # {{{
	my %params = @_;
	return $params{content};
} # }}}

# FIXME: copied verbatim from meta
sub safeurl ($) { #{{{
	my $url=shift;
	if (exists $IkiWiki::Plugin::htmlscrubber::{safe_url_regexp} &&
	    defined $IkiWiki::Plugin::htmlscrubber::safe_url_regexp) {
		return $url=~/$IkiWiki::Plugin::htmlscrubber::safe_url_regexp/;
	}
	else {
		return 1;
	}
} #}}}

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

	# set metadata, possibly overriding [[!meta]] directives from the
	# comment itself

	my $commentuser;
	my $commentip;
	my $commentauthor;
	my $commentauthorurl;

	if (defined $params{username}) {
		$commentuser = $params{username};
		($commentauthorurl, $commentauthor) =
			linkuser($params{username});
	}
	else {
		if (defined $params{ip}) {
			$commentip = $params{ip};
		}
		$commentauthor = gettext("Anonymous");
	}

	$pagestate{$page}{comments}{commentuser} = $commentuser;
	$pagestate{$page}{comments}{commentip} = $commentip;
	$pagestate{$page}{comments}{commentauthor} = $commentauthor;
	$pagestate{$page}{comments}{commentauthorurl} = $commentauthorurl;
	if (!defined $pagestate{$page}{meta}{author}) {
		$pagestate{$page}{meta}{author} = $commentauthor;
	}
	if (!defined $pagestate{$page}{meta}{authorurl}) {
		$pagestate{$page}{meta}{authorurl} = $commentauthorurl;
	}

	if ($config{comments_allowauthor}) {
		if (defined $params{claimedauthor}) {
			$pagestate{$page}{meta}{author} = $params{claimedauthor};
		}

		if (defined $params{url} and safeurl($params{url})) {
			$pagestate{$page}{meta}{authorurl} = $params{url};
		}
	}
	else {
		$pagestate{$page}{meta}{author} = $commentauthor;
		$pagestate{$page}{meta}{authorurl} = $commentauthorurl;
	}

	if (defined $params{subject}) {
		$pagestate{$page}{meta}{title} = $params{subject};
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

sub checkconfig () { #{{{
	$config{comments_commit} = 1 unless defined $config{comments_commit};
	$config{comments_pagename} = 'comment_'
		unless defined $config{comments_pagename};
} #}}}

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
		fields => [qw{do sid page subject editcontent type author url}],
		charset => 'utf-8',
		method => 'POST',
		required => [qw{editcontent}],
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

	my $type = $form->param('type');
	if (defined $type && length $type && $IkiWiki::hooks{htmlize}{$type}) {
		$type = IkiWiki::possibly_foolish_untaint($type);
	}
	else {
		$type = $config{default_pageext};
	}
	my @page_types;
	if (exists $IkiWiki::hooks{htmlize}) {
		@page_types = grep { !/^_/ } keys %{$IkiWiki::hooks{htmlize}};
	}

	my $allow_author = $config{comments_allowauthor};

	$form->field(name => 'do', type => 'hidden');
	$form->field(name => 'sid', type => 'hidden', value => $session->id,
		force => 1);
	$form->field(name => 'page', type => 'hidden');
	$form->field(name => 'subject', type => 'text', size => 72);
	$form->field(name => 'editcontent', type => 'textarea', rows => 10);
	$form->field(name => "type", value => $type, force => 1,
		type => 'select', options => \@page_types);

	$form->tmpl_param(username => $session->param('name'));

	if ($allow_author and !defined $session->param('name')) {
		$form->tmpl_param(allowauthor => 1);
		$form->field(name => 'author', type => 'text', size => '40');
		$form->field(name => 'url', type => 'text', size => '40');
	}
	else {
		$form->tmpl_param(allowauthor => 0);
		$form->field(name => 'author', type => 'hidden', value => '',
			force => 1);
		$form->field(name => 'url', type => 'hidden', value => '',
			force => 1);
	}

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

	# Set a flag to indicate that we're posting a comment,
	# so that postcomment() can tell it should match.
	$postcomment=1;
	IkiWiki::check_canedit($page, $cgi, $session);
	$postcomment=0;

	my $editcontent = $form->field('editcontent') || '';
	$editcontent =~ s/\r\n/\n/g;
	$editcontent =~ s/\r/\n/g;

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

	$editcontent =~ s/"/\\"/g;
	my $content = "[[!_comment format=$type\n";

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

	if ($allow_author) {
		my $author = $form->field('author');
		if (length $author) {
			$author =~ s/"/&quot;/g;
			$content .= " claimedauthor=\"$author\"\n";
		}
		my $url = $form->field('url');
		if (length $url) {
			$url =~ s/"/&quot;/g;
			$content .= " url=\"$url\"\n";
		}
	}

	my $subject = $form->field('subject');
	if (length $subject) {
		$subject =~ s/"/&quot;/g;
		$content .= " subject=\"$subject\"\n";
	}

	$content .= " date=\"" . decode_utf8(strftime('%Y-%m-%dT%H:%M:%SZ', gmtime)) . "\"\n";

	$content .= " content=\"\"\"\n$editcontent\n\"\"\"]]\n";

	# This is essentially a simplified version of editpage:
	# - the user does not control the page that's created, only the parent
	# - it's always a create operation, never an edit
	# - this means that conflicts should never happen
	# - this means that if they do, rocks fall and everyone dies

	if ($form->submitted eq PREVIEW) {
		my $preview = IkiWiki::htmlize($location, $page, '_comment',
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
			$comments = IkiWiki::preprocess_inline(
				pages => "internal($page/${comments_pagename}*)",
				template => 'comments_display',
				show => 0,
				reverse => 'yes',
				page => $page,
				destpage => $params{destpage},
				feedfile => 'comments',
				emptyfeeds => 'no',
			);
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

	if ($template->query(name => 'commentuser')) {
		$template->param(commentuser =>
			$pagestate{$page}{comments}{commentuser});
	}

	if ($template->query(name => 'commentip')) {
		$template->param(commentip =>
			$pagestate{$page}{comments}{commentip});
	}

	if ($template->query(name => 'commentauthor')) {
		$template->param(commentauthor =>
			$pagestate{$page}{comments}{commentauthor});
	}

	if ($template->query(name => 'commentauthorurl')) {
		$template->param(commentauthorurl =>
			$pagestate{$page}{comments}{commentauthorurl});
	}
} # }}}

package IkiWiki::PageSpec;

sub match_postcomment ($$;@) {
	my $page = shift;
	my $glob = shift;

	if (! $postcomment) {
		return IkiWiki::FailReason->new("not posting a comment");
	}
	return match_glob($page, $glob);
}

1
