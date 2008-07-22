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

sub check_canrename ($$$$$$$) { #{{{
	my $src=shift;
	my $srcfile=shift;
	my $dest=shift;
	my $destfile=shift;
	my $q=shift;
	my $session=shift;
	my $attachment=shift;

	# Must be a known source file.
	if (! exists $pagesources{$src}) {
		error(sprintf(gettext("%s does not exist"),
			htmllink("", "", $src, noimageinline => 1)));
	}
	
	# Must exist on disk, and be a regular file.
	if (! -e "$config{srcdir}/$srcfile") {
		error(sprintf(gettext("%s is not in the srcdir, so it cannot be renamed"), $srcfile));
	}
	elsif (-l "$config{srcdir}/$srcfile" && ! -f _) {
		error(sprintf(gettext("%s is not a file"), $srcfile));
	}

	# Must be editable.
	IkiWiki::check_canedit($src, $q, $session);
	if ($attachment) {
		IkiWiki::Plugin::attachment::check_canattach($session, $src, $srcfile);
	}
	
	# Dest checks can be omitted by passing undef.
	if (defined $dest) {
		if ($src eq $dest || $srcfile eq $destfile) {
			error(gettext("no change to the file name was specified"));
		}

		# Must be a legal filename.	
		if (IkiWiki::file_pruned($destfile, $config{srcdir})) {
			error(sprintf(gettext("illegal name")));
		}

		# Must not be a known source file.
		if (exists $pagesources{$dest}) {
			error(sprintf(gettext("%s already exists"),
				htmllink("", "", $dest, noimageinline => 1)));
		}
	
		# Must not exist on disk already.
		if (-l "$config{srcdir}/$destfile" || -e _) {
			error(sprintf(gettext("%s already exists on disk"), $destfile));
		}
	
		# Must be editable.
		IkiWiki::check_canedit($dest, $q, $session);
		if ($attachment) {
			IkiWiki::Plugin::attachment::check_canattach($session, $dest, $destfile);
		}
	}
} #}}}

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

	check_canrename($page, $pagesources{$page}, undef, undef,
		$q, $session, $attachment);

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
			# These untaints are safe because of the checks
			# performed in check_canrename below.
			my $src=$q->param("page");
			my $srcfile=IkiWiki::possibly_foolish_untaint($pagesources{$src});
			my $dest=IkiWiki::possibly_foolish_untaint(IkiWiki::titlepage($q->param("new_name")));

			# The extension of dest is the same as src if it's
			# a page. If it's an extension, the extension is
			# already included.
			my $destfile=$dest;
			if (! $q->param("attachment")) {
				my ($ext)=$srcfile=~/(\.[^.]+)$/;
				$destfile.=$ext;
			}

			check_canrename($src, $srcfile, $dest, $destfile,
				$q, $session, $q->param("attachment"));

			# Do rename, and update the wiki.
			require IkiWiki::Render;
			if ($config{rcs}) {
				IkiWiki::disable_commit_hook();
				my $token=IkiWiki::rcs_prepedit($srcfile);
				IkiWiki::rcs_rename($srcfile, $destfile);
				# TODO commit destfile too
				IkiWiki::rcs_commit($srcfile, gettext("rename $srcfile to $destfile"),
					$token, $session->param("name"), $ENV{REMOTE_ADDR});
				IkiWiki::enable_commit_hook();
				IkiWiki::rcs_update();
			}
			else {
				if (! rename("$config{srcdir}/$srcfile", "$config{srcdir}/$destfile")) {
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
