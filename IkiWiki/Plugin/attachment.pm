#!/usr/bin/perl
package IkiWiki::Plugin::attachment;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "checkconfig", id => "attachment", call => \&checkconfig);
	hook(type => "formbuilder_setup", id => "attachment", call => \&formbuilder_setup);
	hook(type => "formbuilder", id => "attachment", call => \&formbuilder);
} # }}}

sub checkconfig () { #{{{
	$config{cgi_disable_uploads}=0;
} #}}}

sub attachment_location ($) {
	my $page=shift;
	
	# Put the attachment in a subdir of the page it's attached
	# to, unless that page is an "index" page.
	$page=~s/(^|\/)index//;
	$page.="/" if length $page;
	
	return $page;
}

sub attachment_list ($) {
	my $loc=attachment_location(shift);

	my @ret;
	foreach my $f (values %pagesources) {
		print STDERR ">>$f\n" if ! defined IkiWiki::pagetype($f);
		if (! defined IkiWiki::pagetype($f) &&
		    $f=~m/^\Q$loc\E[^\/]+$/ &&
		    -e "$config{srcdir}/$f") {
			push @ret, {
				"field-select" => '<input type="checkbox" name="attachment_select" value="'.$f.'">',
				link => $f,
				size => (stat(_))[7],
				mtime => displaytime($IkiWiki::pagemtime{$f}),
			};
		}
	}

	return @ret;
}

sub formbuilder_setup (@) { #{{{
	my %params=@_;
	my $form=$params{form};

	if ($form->field("do") eq "edit") {
		$form->field(name => 'attachment', type => 'file');
		$form->tmpl_param("attachment_list" => [attachment_list($form->field('page'))]);

		# These buttons are not put in the usual place, so
		# is not added to the normal formbuilder button list.
		$form->tmpl_param("field-upload" => '<input name="_submit" type="submit" value="Upload Attachment" />');
		$form->tmpl_param("field-link" => '<input name="_submit" type="submit" value="Insert Links" />');
	}
	elsif ($form->title eq "preferences") {
		my $session=$params{session};
		my $user_name=$session->param("name");

		$form->field(name => "allowed_attachments", size => 50,
			fieldset => "admin",
			comment => "(".htmllink("", "", "ikiwiki/PageSpec", noimageinline => 1).")");
		if (! IkiWiki::is_admin($user_name)) {
			$form->field(name => "allowed_attachments", type => "hidden");
		}
                if (! $form->submitted) {
			$form->field(name => "allowed_attachments", force => 1,
				value => IkiWiki::userinfo_get($user_name, "allowed_attachments"));
                }
		if ($form->submitted && $form->submitted eq 'Save Preferences') {
			if (defined $form->field("allowed_attachments")) {
				IkiWiki::userinfo_set($user_name, "allowed_attachments",
				$form->field("allowed_attachments")) ||
					error("failed to set allowed_attachments");
			}
		}
	}
} #}}}

sub formbuilder (@) { #{{{
	my %params=@_;
	my $form=$params{form};

	return if $form->field("do") ne "edit";

	if ($form->submitted eq "Upload" || $form->submitted eq "Save Page") {
		my $q=$params{cgi};
		my $session=$params{session};

		my $filename=$q->param('attachment');
		if (! defined $filename || ! length $filename) {
			# no file, so do nothing
			return;
		}
		
		# This is an (apparently undocumented) way to get the name
		# of the temp file that CGI writes the upload to.
		my $tempfile=$q->tmpFileName($filename);
		
		$filename=IkiWiki::titlepage(
			IkiWiki::possibly_foolish_untaint(
				attachment_location($form->field('page')).
				IkiWiki::basename($filename)));
		if (IkiWiki::file_pruned($filename, $config{srcdir})) {
			error(gettext("bad attachment filename"));
		}
		
		# Check that the user is allowed to edit a page with the
		# name of the attachment.
		IkiWiki::check_canedit($filename, $q, $session, 1);
		
		# Use a special pagespec to test that the attachment is valid.
		my $allowed=1;
		foreach my $admin (@{$config{adminuser}}) {
			my $allowed_attachments=IkiWiki::userinfo_get($admin, "allowed_attachments");
			if (defined $allowed_attachments &&
			    length $allowed_attachments) {
				$allowed=pagespec_match($filename,
					$allowed_attachments,
					file => $tempfile);
				last if $allowed;
			}
		}
		if (! $allowed) {
			error(gettext("attachment rejected")." ($allowed)");
		}

		# Needed for fast_file_copy and for rendering below.
		require IkiWiki::Render;

		# Move the attachment into place.
		# Try to use a fast rename; fall back to copying.
		IkiWiki::prep_writefile($filename, $config{srcdir});
		unlink($config{srcdir}."/".$filename);
		if (! rename($tempfile, $config{srcdir}."/".$filename)) {
			my $fh=$q->upload('attachment');
			if (! defined $fh || ! ref $fh) {
				error("failed to get filehandle");
			}
			binmode($fh);
			writefile($filename, $config{srcdir}, undef, 1, sub {
				IkiWiki::fast_file_copy($tempfile, $filename, $fh, @_);
			});
		}

		# Check the attachment in and trigger a wiki refresh.
		if ($config{rcs}) {
			IkiWiki::rcs_add($filename);
			IkiWiki::disable_commit_hook();
			IkiWiki::rcs_commit($filename, gettext("attachment upload"),
				IkiWiki::rcs_prepedit($filename),
				$session->param("name"), $ENV{REMOTE_ADDR});
			IkiWiki::enable_commit_hook();
			IkiWiki::rcs_update();
		}
		IkiWiki::refresh();
		IkiWiki::saveindex();
	}
} # }}}

package IkiWiki::PageSpec;

sub parsesize ($) { #{{{
	my $size=shift;
	no warnings;
	my $base=$size+0; # force to number
	use warnings;
	my $multiple=1;
	if ($size=~/kb?$/i) {
		$multiple=2**10;
	}
	elsif ($size=~/mb?$/i) {
		$multiple=2**20;
	}
	elsif ($size=~/gb?$/i) {
		$multiple=2**30;
	}
	elsif ($size=~/tb?$/i) {
		$multiple=2**40;
	}
	return $base * $multiple;
} #}}}

sub match_maxsize ($$;@) { #{{{
	shift;
	my $maxsize=eval{parsesize(shift)};
	if ($@) {
		return IkiWiki::FailReason->new("unable to parse maxsize (or number too large)");
	}

	my %params=@_;
	if (! exists $params{file}) {
		return IkiWiki::FailReason->new("no file specified");
	}

	if (-s $params{file} > $maxsize) {
		return IkiWiki::FailReason->new("file too large");
	}
	else {
		return IkiWiki::SuccessReason->new("file not too large");
	}
} #}}}

sub match_minsize ($$;@) { #{{{
	shift;
	my $minsize=eval{parsesize(shift)};
	if ($@) {
		return IkiWiki::FailReason->new("unable to parse minsize (or number too large)");
	}

	my %params=@_;
	if (! exists $params{file}) {
		return IkiWiki::FailReason->new("no file specified");
	}

	if (-s $params{file} < $minsize) {
		return IkiWiki::FailReason->new("file too small");
	}
	else {
		return IkiWiki::SuccessReason->new("file not too small");
	}
} #}}}

sub match_ispage ($$;@) { #{{{
	my $filename=shift;

	if (defined IkiWiki::pagetype($filename)) {
		return IkiWiki::SuccessReason->new("file is a wiki page");
	}
	else {
		return IkiWiki::FailReason->new("file is not a wiki page");
	}
} #}}}

1
