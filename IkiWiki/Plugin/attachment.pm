#!/usr/bin/perl
package IkiWiki::Plugin::attachment;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "getsetup", id => "attachment", call => \&getsetup);
	hook(type => "checkconfig", id => "attachment", call => \&checkconfig);
	hook(type => "formbuilder_setup", id => "attachment", call => \&formbuilder_setup);
	hook(type => "formbuilder", id => "attachment", call => \&formbuilder);
	IkiWiki::loadplugin("filecheck");
} # }}}

sub getsetup () { #{{{
	return
		plugin => {
			safe => 1,
			rebuild => 0,
		},
		allowed_attachments => {
			type => "pagespec",
			example => "virusfree() and mimetype(image/*) and maxsize(50kb)",
			description => "enhanced PageSpec specifying what attachments are allowed",
			link => "ikiwiki/PageSpec/attachment",
			safe => 1,
			rebuild => 0,
		},
		virus_checker => {
			type => "string",
			example => "clamdscan -",
			description => "virus checker program (reads STDIN, returns nonzero if virus found)",
			safe => 0, # executed
			rebuild => 0,
		},
} #}}}

sub check_canattach ($$;$) { #{{{
	my $session=shift;
	my $dest=shift; # where it's going to be put, under the srcdir
	my $file=shift; # the path to the attachment currently

	# Don't allow an attachment to be uploaded with the same name as an
	# existing page.
	if (exists $IkiWiki::pagesources{$dest} &&
	    $IkiWiki::pagesources{$dest} ne $dest) {
		error(sprintf(gettext("there is already a page named %s"), $dest));
	}

	# Use a special pagespec to test that the attachment is valid.
	my $allowed=1;
	if (defined $config{allowed_attachments} &&
	    length $config{allowed_attachments}) {
		$allowed=pagespec_match($dest,
			$config{allowed_attachments},
			file => $file,
			user => $session->param("name"),
			ip => $ENV{REMOTE_ADDR},
		);
	}

	# XXX deprecated, should be removed eventually
	if ($allowed) {
		foreach my $admin (@{$config{adminuser}}) {
			my $allowed_attachments=IkiWiki::userinfo_get($admin, "allowed_attachments");
			if (defined $allowed_attachments &&
			    length $allowed_attachments) {
				$allowed=pagespec_match($dest,
					$allowed_attachments,
					file => $file,
					user => $session->param("name"),
					ip => $ENV{REMOTE_ADDR},
				);
				last if $allowed;
			}
		}
	}

	if (! $allowed) {
		error(gettext("prohibited by allowed_attachments")." ($allowed)");
	}
	else {
		return 1;
	}
} #}}}

sub checkconfig () { #{{{
	$config{cgi_disable_uploads}=0;
} #}}}

sub formbuilder_setup (@) { #{{{
	my %params=@_;
	my $form=$params{form};
	my $q=$params{cgi};

	if (defined $form->field("do") && $form->field("do") eq "edit") {
		# Add attachment field, set type to multipart.
		$form->enctype(&CGI::MULTIPART);
		$form->field(name => 'attachment', type => 'file');
		# These buttons are not put in the usual place, so
		# are not added to the normal formbuilder button list.
		$form->tmpl_param("field-upload" => '<input name="_submit" type="submit" value="Upload Attachment" />');
		$form->tmpl_param("field-link" => '<input name="_submit" type="submit" value="Insert Links" />');

		# Add the javascript from the toggle plugin;
		# the attachments interface uses it to toggle visibility.
		require IkiWiki::Plugin::toggle;
		$form->tmpl_param("javascript" => $IkiWiki::Plugin::toggle::javascript);
		# Start with the attachments interface toggled invisible,
		# but if it was used, keep it open.
		if ($form->submitted ne "Upload Attachment" &&
		    (! defined $q->param("attachment_select") ||
		    ! length $q->param("attachment_select"))) {
			$form->tmpl_param("attachments-class" => "toggleable");
		}
		else {
			$form->tmpl_param("attachments-class" => "toggleable-open");
		}
	}
	elsif ($form->title eq "preferences") {
		# XXX deprecated, should remove eventually
		my $session=$params{session};
		my $user_name=$session->param("name");

		$form->field(name => "allowed_attachments", size => 50,
			fieldset => "admin",
			comment => "deprecated; please move to allowed_attachments in setup file",
		);
		if (! IkiWiki::is_admin($user_name)) {
			$form->field(name => "allowed_attachments", type => "hidden");
		}
                if (! $form->submitted) {
			my $value=IkiWiki::userinfo_get($user_name, "allowed_attachments");
			if (length $value) {
				$form->field(name => "allowed_attachments", force => 1,
					value => IkiWiki::userinfo_get($user_name, "allowed_attachments"));
			}
			else {
				$form->field(name => "allowed_attachments", type => "hidden");
			}
                }
		if ($form->submitted && $form->submitted eq 'Save Preferences') {
			if (defined $form->field("allowed_attachments")) {
				IkiWiki::userinfo_set($user_name, "allowed_attachments",
				$form->field("allowed_attachments")) ||
					error("failed to set allowed_attachments");
				if (! length $form->field("allowed_attachments")) {
					$form->field(name => "allowed_attachments", type => "hidden");
				}
			}
		}
	}
} #}}}

sub formbuilder (@) { #{{{
	my %params=@_;
	my $form=$params{form};
	my $q=$params{cgi};

	return if ! defined $form->field("do") || $form->field("do") ne "edit";

	my $filename=$q->param('attachment');
	if (defined $filename && length $filename &&
            ($form->submitted eq "Upload Attachment" || $form->submitted eq "Save Page")) {
		my $session=$params{session};
		
		# This is an (apparently undocumented) way to get the name
		# of the temp file that CGI writes the upload to.
		my $tempfile=$q->tmpFileName($filename);
		if (! defined $tempfile || ! length $tempfile) {
			# perl 5.8 needs an alternative, awful method
			if ($q =~ /HASH/ && exists $q->{'.tmpfiles'}) {
				foreach my $key (keys(%{$q->{'.tmpfiles'}})) {
					$tempfile=$q->tmpFileName(\$key);
					last if defined $tempfile && length $tempfile;
				}
			}
			if (! defined $tempfile || ! length $tempfile) {
				error("CGI::tmpFileName failed to return the uploaded file name");
			}
		}

		$filename=IkiWiki::linkpage(
			IkiWiki::possibly_foolish_untaint(
				attachment_location($form->field('page')).
				IkiWiki::basename($filename)));
		if (IkiWiki::file_pruned($filename, $config{srcdir})) {
			error(gettext("bad attachment filename"));
		}
		
		# Check that the user is allowed to edit a page with the
		# name of the attachment.
		IkiWiki::check_canedit($filename, $q, $session, 1);
		# And that the attachment itself is acceptable.
		check_canattach($session, $filename, $tempfile);

		# Needed for fast_file_copy and for rendering below.
		require IkiWiki::Render;

		# Move the attachment into place.
		# Try to use a fast rename; fall back to copying.
		IkiWiki::prep_writefile($filename, $config{srcdir});
		unlink($config{srcdir}."/".$filename);
		if (rename($tempfile, $config{srcdir}."/".$filename)) {
			# The temp file has tight permissions; loosen up.
			chmod(0666 & ~umask, $config{srcdir}."/".$filename);
		}
		else {
			my $fh=$q->upload('attachment');
			if (! defined $fh || ! ref $fh) {
				# needed by old CGI versions
				$fh=$q->param('attachment');
				if (! defined $fh || ! ref $fh) {
					# even that doesn't always work,
					# fall back to opening the tempfile
					$fh=undef;
					open($fh, "<", $tempfile) || error("failed to open \"$tempfile\": $!");
				}
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
	elsif ($form->submitted eq "Insert Links") {
		my $page=quotemeta($q->param("page"));
		my $add="";
		foreach my $f ($q->param("attachment_select")) {
			$f=~s/^$page\///;
			$add.="[[$f]]\n";
		}
		$form->field(name => 'editcontent',
			value => $form->field('editcontent')."\n\n".$add,
			force => 1) if length $add;
	}
	
	# Generate the attachment list only after having added any new
	# attachments.
	$form->tmpl_param("attachment_list" => [attachment_list($form->field('page'))]);
} # }}}

sub attachment_location ($) { #{{{
	my $page=shift;
	
	# Put the attachment in a subdir of the page it's attached
	# to, unless that page is an "index" page.
	$page=~s/(^|\/)index//;
	$page.="/" if length $page;
	
	return $page;
} #}}}

sub attachment_list ($) { #{{{
	my $page=shift;
	my $loc=attachment_location($page);

	my @ret;
	foreach my $f (values %pagesources) {
		if (! defined IkiWiki::pagetype($f) &&
		    $f=~m/^\Q$loc\E[^\/]+$/ &&
		    -e "$config{srcdir}/$f") {
			push @ret, {
				"field-select" => '<input type="checkbox" name="attachment_select" value="'.$f.'" />',
				link => htmllink($page, $page, $f, noimageinline => 1),
				size => IkiWiki::Plugin::filecheck::humansize((stat(_))[7]),
				mtime => displaytime($IkiWiki::pagemtime{$f}),
				mtime_raw => $IkiWiki::pagemtime{$f},
			};
		}
	}

	# Sort newer attachments to the top of the list, so a newly-added
	# attachment appears just before the form used to add it.
	return sort { $b->{mtime_raw} <=> $a->{mtime_raw} || $a->{link} cmp $b->{link} } @ret;
} #}}}

package IkiWiki::PageSpec;

sub match_user ($$;@) { #{{{
	shift;
	my $user=shift;
	my %params=@_;
	
	if (! exists $params{user}) {
		return IkiWiki::FailReason->new("no user specified");
	}

	if (defined $params{user} && lc $params{user} eq lc $user) {
		return IkiWiki::SuccessReason->new("user is $user");
	}
	elsif (! defined $params{user}) {
		return IkiWiki::FailReason->new("not logged in");
	}
	else {
		return IkiWiki::FailReason->new("user is $params{user}, not $user");
	}
} #}}}

sub match_admin ($$;@) { #{{{
	shift;
	shift;
	my %params=@_;
	
	if (! exists $params{user}) {
		return IkiWiki::FailReason->new("no user specified");
	}

	if (defined $params{user} && IkiWiki::is_admin($params{user})) {
		return IkiWiki::SuccessReason->new("user is an admin");
	}
	elsif (! defined $params{user}) {
		return IkiWiki::FailReason->new("not logged in");
	}
	else {
		return IkiWiki::FailReason->new("user is not an admin");
	}
} #}}}

sub match_ip ($$;@) { #{{{
	shift;
	my $ip=shift;
	my %params=@_;
	
	if (! exists $params{ip}) {
		return IkiWiki::FailReason->new("no IP specified");
	}

	if (defined $params{ip} && lc $params{ip} eq lc $ip) {
		return IkiWiki::SuccessReason->new("IP is $ip");
	}
	else {
		return IkiWiki::FailReason->new("IP is $params{ip}, not $ip");
	}
} #}}}

1
