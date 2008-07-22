#!/usr/bin/perl
package IkiWiki::Plugin::rename;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "formbuilder_setup", id => "rename", call => \&formbuilder_setup);
	hook(type => "formbuilder", id => "rename", call => \&formbuilder);
	hook(type => "sessioncgi", id => "rename", call => \&sessioncgi);

} # }}}

sub formbuilder_setup (@) { #{{{
	my %params=@_;
	my $form=$params{form};
	my $q=$params{cgi};

	if (defined $form->field("do") && $form->field("do") eq "edit") {
		# Rename button for the page, and also for attachments.
		push @{$params{buttons}}, "Rename";
		$form->tmpl_param("field-rename" => '<input name="_submit" type="submit" value="Rename Attachment" />');
	}
} #}}}

sub rename_form ($$$) { #{{{ 
	my $q=shift;
	my $session=shift;
	my $page=shift;

	eval q{use CGI::FormBuilder};
	error($@) if $@;
	my $f = CGI::FormBuilder->new(
		name => "rename",
		title => sprintf(gettext("rename %s"), IkiWiki::pagetitle($page)),
		header => 0,
		charset => "utf-8",
		method => 'POST',
		javascript => 0,
		params => $q,
		action => $config{cgiurl},
		stylesheet => IkiWiki::baseurl()."style.css",
		fields => [qw{do page new_name attachment}],
	);
	
	$f->field(name => "do", type => "hidden", value => "rename", force => 1);
	$f->field(name => "page", type => "hidden", value => $page, force => 1);
	$f->field(name => "new_name", value => IkiWiki::pagetitle($page), size => 60);
	$f->field(name => "attachment", type => "hidden");

	return $f, ["Rename", "Cancel"];
} #}}}

sub rename_start ($$$$) {
	my $q=shift;
	my $session=shift;
	my $attachment=shift;
	my $page=shift;

   	# Save current form state to allow returning to it later
	# without losing any edits.
	# (But don't save what button was submitted, to avoid
	# looping back to here.)
	# Note: "_submit" is CGI::FormBuilder internals.
	$q->param(-name => "_submit", -value => "");
	$session->param(postrename => scalar $q->Vars);
	IkiWiki::cgi_savesession($session);
	
	my ($f, $buttons)=rename_form($q, $session, $page);
	if (defined $attachment) {
		$f->field(name => "attachment", value => $attachment, force => 1);
	}
	
	IkiWiki::showform($f, $buttons, $session, $q);
	exit 0;
}

sub postrename ($;$) {
	my $session=shift;
	my $newname=shift;

	# Load saved form state and return to edit form.
	my $postrename=CGI->new($session->param("postrename"));
	if (defined $newname) {
		# They renamed the page they were editing.
		# Tweak the edit form to be editing the new
		# page name, and redirect back to it.
		# (Deep evil here.)
		error("don't know how to redir back!"); ## FIXME
	}
	$session->clear("postrename");
	IkiWiki::cgi_savesession($session);
	IkiWiki::cgi($postrename, $session);
}

sub formbuilder (@) { #{{{
	my %params=@_;
	my $form=$params{form};

	if (defined $form->field("do") && $form->field("do") eq "edit") {
		my $q=$params{cgi};
		my $session=$params{session};

		if ($form->submitted eq "Rename") {
			rename_start($q, $session, 0, $form->field("page"));
		}
		elsif ($form->submitted eq "Rename Attachment") {
			my @selected=$q->param("attachment_select");
			if (@selected > 1) {
				error(gettext("Only one attachment can be renamed at a time."));
			}
			elsif (! @selected) {
				error(gettext("Please select the attachment to rename."))
			}
			rename_start($q, $session, 1, $selected[0]);
		}
	}
} #}}}

sub sessioncgi ($$) { #{{{
        my $q=shift;

	if ($q->param("do") eq 'rename') {
        	my $session=shift;
		my ($form, $buttons)=rename_form($q, $session, $q->param("page"));
		IkiWiki::decode_form_utf8($form);

		if ($form->submitted eq 'Cancel') {
			postrename($session);
		}
		elsif ($form->submitted eq 'Rename' && $form->validate) {
			my $page=$q->param("page");

			# This untaint is safe because of the checks below.
			my $file=IkiWiki::possibly_foolish_untaint($pagesources{$page});

			# Must be a known source file.
			if (! defined $file) {
				error(sprintf(gettext("%s does not exist"),
				htmllink("", "", $page, noimageinline => 1)));
			}
				
			# Must be editiable.
			IkiWiki::check_canedit($page, $q, $session);

			# Must exist on disk, and be a regular file.
			if (! -e "$config{srcdir}/$file") {
				error(sprintf(gettext("%s is not in the srcdir, so it cannot be deleted"), $file));
			}
			elsif (-l "$config{srcdir}/$file" && ! -f _) {
				error(sprintf(gettext("%s is not a file"), $file));
			}

			# TODO: check attachment limits

			my $dest=IkiWiki::titlepage($q->param("new_name"));
			# XXX TODO check $dest!

			# Do rename, and update the wiki.
			require IkiWiki::Render;
			if ($config{rcs}) {
				IkiWiki::disable_commit_hook();
				my $token=IkiWiki::rcs_prepedit($file);
				IkiWiki::rcs_rename($file, $dest);
				IkiWiki::rcs_commit($file, gettext("rename $file to $dest"),
					$token, $session->param("name"), $ENV{REMOTE_ADDR});
				IkiWiki::enable_commit_hook();
				IkiWiki::rcs_update();
			}
			else {
				if (! rename("$config{srcdir}/$file", "$config{srcdir}/$dest")) {
					error("rename: $!");
				}
			}
			IkiWiki::refresh();
			IkiWiki::saveindex();

			if ($q->param("attachment")) {
				postrename($session);
			}
			else {
				postrename($session, $dest);
			}
		}
		else {
			IkiWiki::showform($form, $buttons, $session, $q);
		}

		exit 0;
	}
}

1
