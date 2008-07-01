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

sub formbuilder_setup (@) { #{{{
	my %params=@_;
	my $form=$params{form};

	if ($form->field("do") eq "edit") {
		$form->field(name => 'attachment', type => 'file');
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

	if ($form->submitted eq "Upload") {
		my $q=$params{cgi};
		my $filename=$q->param('attachment');
		if (! defined $filename || ! length $filename) {
			# no file, so do nothing
			return;
		}
		
		# This is an (apparently undocumented) way to get the name
		# of the temp file that CGI writes the upload to.
		my $tempfile=$q->tmpFileName($filename);
		
		# Put the attachment in a subdir of the page it's attached
		# to, unless that page is an "index" page.
		my $page=$form->field('page');
		$page=~s/(^|\/)index//;
		$filename=$page."/".IkiWiki::basename($filename);
		
		# To untaint the filename, escape any hazardous characters,
		# and make sure it isn't pruned.
		$filename=IkiWiki::titlepage(IkiWiki::possibly_foolish_untaint($filename));
		if (IkiWiki::file_pruned($filename, $config{srcdir})) {
			error(gettext("bad attachment filename"));
		}
		
		# Check that the user is allowed to edit a page with the
		# name of the attachment.
		IkiWiki::check_canedit($filename, $q, $params{session}, 1);
		
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

		# Needed for fast_file_copy.
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

		# TODO add to vcs
		
		# TODO trigger a wiki build if there's no vcs
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
