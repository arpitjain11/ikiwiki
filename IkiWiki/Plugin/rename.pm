#!/usr/bin/perl
package IkiWiki::Plugin::rename;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "rename", call => \&getsetup);
	hook(type => "formbuilder_setup", id => "rename", call => \&formbuilder_setup);
	hook(type => "formbuilder", id => "rename", call => \&formbuilder);
	hook(type => "sessioncgi", id => "rename", call => \&sessioncgi);

}

sub getsetup () {
	return 
		plugin => {
			safe => 1,
			rebuild => 0,
		},
}

sub check_canrename ($$$$$$) {
	my $src=shift;
	my $srcfile=shift;
	my $dest=shift;
	my $destfile=shift;
	my $q=shift;
	my $session=shift;

	my $attachment=! defined pagetype($pagesources{$src});

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
		if (IkiWiki::Plugin::attachment->can("check_canattach")) {
			IkiWiki::Plugin::attachment::check_canattach($session, $src, $srcfile);
		}
		else {
			error("renaming of attachments is not allowed");
		}
	}
	
	# Dest checks can be omitted by passing undef.
	if (defined $dest) {
		if ($srcfile eq $destfile) {
			error(gettext("no change to the file name was specified"));
		}

		# Must be a legal filename, and not absolute.
		if (IkiWiki::file_pruned($destfile, $config{srcdir}) || 
		    $destfile=~/^\//) {
			error(sprintf(gettext("illegal name")));
		}

		# Must not be a known source file.
		if ($src ne $dest && exists $pagesources{$dest}) {
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
			# Note that $srcfile is used here, not $destfile,
			# because it wants the current file, to check it.
			IkiWiki::Plugin::attachment::check_canattach($session, $dest, $srcfile);
		}
	}
}

sub rename_form ($$$) {
	my $q=shift;
	my $session=shift;
	my $page=shift;

	eval q{use CGI::FormBuilder};
	error($@) if $@;
	my $f = CGI::FormBuilder->new(
		name => "rename",
		title => sprintf(gettext("rename %s"), pagetitle($page)),
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
	$f->field(name => "new_name", value => pagetitle($page, 1), size => 60);
	if (!$q->param("attachment")) {
		# insert the standard extensions
		my @page_types;
		if (exists $IkiWiki::hooks{htmlize}) {
			@page_types=grep { !/^_/ }
				keys %{$IkiWiki::hooks{htmlize}};
		}
	
		# make sure the current extension is in the list
		my ($ext) = $pagesources{$page}=~/\.([^.]+)$/;
		if (! $IkiWiki::hooks{htmlize}{$ext}) {
			unshift(@page_types, $ext);
		}
	
		$f->field(name => "type", type => 'select',
			options => \@page_types,
			value => $ext, force => 1);
		
		foreach my $p (keys %pagesources) {
			if ($pagesources{$p}=~m/^\Q$page\E\//) {
				$f->field(name => "subpages",
					label => "",
					type => "checkbox",
					options => [ [ 1 => gettext("Also rename SubPages and attachments") ] ],
					value => 1,
					force => 1);
				last;
			}
		}
	}
	$f->field(name => "attachment", type => "hidden");

	return $f, ["Rename", "Cancel"];
}

sub rename_start ($$$$) {
	my $q=shift;
	my $session=shift;
	my $attachment=shift;
	my $page=shift;

	check_canrename($page, $pagesources{$page}, undef, undef,
		$q, $session);

   	# Save current form state to allow returning to it later
	# without losing any edits.
	# (But don't save what button was submitted, to avoid
	# looping back to here.)
	# Note: "_submit" is CGI::FormBuilder internals.
	$q->param(-name => "_submit", -value => "");
	$session->param(postrename => scalar $q->Vars);
	IkiWiki::cgi_savesession($session);
	
	if (defined $attachment) {
		$q->param(-name => "attachment", -value => $attachment);
	}
	my ($f, $buttons)=rename_form($q, $session, $page);
	IkiWiki::showform($f, $buttons, $session, $q);
	exit 0;
}

sub postrename ($;$$$) {
	my $session=shift;
	my $src=shift;
	my $dest=shift;
	my $attachment=shift;

	# Load saved form state and return to edit page.
	my $postrename=CGI->new($session->param("postrename"));
	$session->clear("postrename");
	IkiWiki::cgi_savesession($session);

	if (defined $dest) {
		if (! $attachment) {
			# They renamed the page they were editing. This requires
			# fixups to the edit form state.
			# Tweak the edit form to be editing the new page.
			$postrename->param("page", $dest);
		}

		# Update edit form content to fix any links present
		# on it.
		$postrename->param("editcontent",
			renamepage_hook($dest, $src, $dest,
				 $postrename->param("editcontent")));

		# Get a new edit token; old was likely invalidated.
		$postrename->param("rcsinfo",
			IkiWiki::rcs_prepedit($pagesources{$dest}));
	}

	IkiWiki::cgi_editpage($postrename, $session);
}

sub formbuilder (@) {
	my %params=@_;
	my $form=$params{form};

	if (defined $form->field("do") && ($form->field("do") eq "edit" ||
	    $form->field("do") eq "create")) {
		my $q=$params{cgi};
		my $session=$params{session};

		if ($form->submitted eq "Rename" && $form->field("do") eq "edit") {
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
}

my $renamesummary;

sub formbuilder_setup (@) {
	my %params=@_;
	my $form=$params{form};
	my $q=$params{cgi};

	if (defined $form->field("do") && ($form->field("do") eq "edit" ||
	    $form->field("do") eq "create")) {
		# Rename button for the page, and also for attachments.
		push @{$params{buttons}}, "Rename" if $form->field("do") eq "edit";
		$form->tmpl_param("field-rename" => '<input name="_submit" type="submit" value="Rename Attachment" />');

		if (defined $renamesummary) {
			$form->tmpl_param(message => $renamesummary);
		}
	}
}

sub sessioncgi ($$) {
        my $q=shift;

	if ($q->param("do") eq 'rename') {
        	my $session=shift;
		my ($form, $buttons)=rename_form($q, $session, $q->param("page"));
		IkiWiki::decode_form_utf8($form);

		if ($form->submitted eq 'Cancel') {
			postrename($session);
		}
		elsif ($form->submitted eq 'Rename' && $form->validate) {
			# Queue of rename actions to perfom.
			my @torename;

			# These untaints are safe because of the checks
			# performed in check_canrename later.
			my $src=$q->param("page");
			my $srcfile=IkiWiki::possibly_foolish_untaint($pagesources{$src});
			my $dest=IkiWiki::possibly_foolish_untaint(titlepage($q->param("new_name")));
			my $destfile=$dest;
			if (! $q->param("attachment")) {
				my $type=$q->param('type');
				if (defined $type && length $type && $IkiWiki::hooks{htmlize}{$type}) {
					$type=IkiWiki::possibly_foolish_untaint($type);
				}
				else {
					my ($ext)=$srcfile=~/\.([^.]+)$/;
					$type=$ext;
				}
				
				$destfile=newpagefile($dest, $type);
			}
			push @torename, {
				src => $src,
			       	srcfile => $srcfile,
				dest => $dest,
			       	destfile => $destfile,
				required => 1,
			};

			# See if any subpages need to be renamed.
			if ($q->param("subpages") && $src ne $dest) {
				foreach my $p (keys %pagesources) {
					next unless $pagesources{$p}=~m/^\Q$src\E\//;
					# If indexpages is enabled, the
					# srcfile should not be confused
					# with a subpage.
					next if $pagesources{$p} eq $srcfile;

					my $d=$pagesources{$p};
					$d=~s/^\Q$src\E\//$dest\//;
					push @torename, {
						src => $p,
						srcfile => $pagesources{$p},
						dest => pagename($d),
						destfile => $d,
						required => 0,
					};
				}
			}
			
			require IkiWiki::Render;
			IkiWiki::disable_commit_hook() if $config{rcs};
			my %origpagesources=%pagesources;

			# First file renaming.
			foreach my $rename (@torename) {
				if ($rename->{required}) {
					do_rename($rename, $q, $session);
				}
				else {
					eval {do_rename($rename, $q, $session)};
					if ($@) {
						$rename->{error}=$@;
						next;
					}
				}

				# Temporarily tweak pagesources to point to
				# the renamed file, in case fixlinks needs
				# to edit it.
				$pagesources{$rename->{src}}=$rename->{destfile};
			}
			IkiWiki::rcs_commit_staged(
				sprintf(gettext("rename %s to %s"), $srcfile, $destfile),
				$session->param("name"), $ENV{REMOTE_ADDR}) if $config{rcs};

			# Then link fixups.
			foreach my $rename (@torename) {
				next if $rename->{src} eq $rename->{dest};
				next if $rename->{error};
				foreach my $p (fixlinks($rename, $session)) {
					# map old page names to new
					foreach my $r (@torename) {
						next if $rename->{error};
						if ($r->{src} eq $p) {
							$p=$r->{dest};
							last;
						}
					}
					push @{$rename->{fixedlinks}}, $p;
				}
			}

			# Then refresh.
			%pagesources=%origpagesources;
			if ($config{rcs}) {
				IkiWiki::enable_commit_hook();
				IkiWiki::rcs_update();
			}
			IkiWiki::refresh();
			IkiWiki::saveindex();

			# Find pages with remaining, broken links.
			foreach my $rename (@torename) {
				next if $rename->{src} eq $rename->{dest};
				
				foreach my $page (keys %links) {
					my $broken=0;
					foreach my $link (@{$links{$page}}) {
						my $bestlink=bestlink($page, $link);
						if ($bestlink eq $rename->{src}) {
							push @{$rename->{brokenlinks}}, $page;
							last;
						}
					}
				}
			}

			# Generate a summary, that will be shown at the top
			# of the edit template.
			$renamesummary="";
			foreach my $rename (@torename) {
				my $template=template("renamesummary.tmpl");
				$template->param(src => $rename->{srcfile});
				$template->param(dest => $rename->{destfile});
				$template->param(error => $rename->{error});
				if ($rename->{src} ne $rename->{dest}) {
					$template->param(brokenlinks_checked => 1);
					$template->param(brokenlinks => linklist($rename->{dest}, $rename->{brokenlinks}));
					$template->param(fixedlinks => linklist($rename->{dest}, $rename->{fixedlinks}));
				}
				$renamesummary.=$template->output;
			}

			postrename($session, $src, $dest, $q->param("attachment"));
		}
		else {
			IkiWiki::showform($form, $buttons, $session, $q);
		}

		exit 0;
	}
}
						
sub linklist {
	# generates a list of links in a form suitable for FormBuilder
	my $dest=shift;
	my $list=shift;
	# converts a list of pages into a list of links
	# in a form suitable for FormBuilder.

	[map {
		{
			page => htmllink($dest, $dest, $_,
					noimageinline => 1,
					linktext => pagetitle($_),
				)
		}
	} @{$list}]
}

sub renamepage_hook ($$$$) {
	my ($page, $src, $dest, $content)=@_;

	IkiWiki::run_hooks(renamepage => sub {
		$content=shift->(
			page => $page,
			oldpage => $src,
			newpage => $dest,
			content => $content,
		);
	});

	return $content;
}
			
sub do_rename ($$$) {
	my $rename=shift;
	my $q=shift;
	my $session=shift;

	# First, check if this rename is allowed.
	check_canrename($rename->{src},
		$rename->{srcfile},
		$rename->{dest},
		$rename->{destfile},
		$q, $session);

	# Ensure that the dest directory exists and is ok.
	IkiWiki::prep_writefile($rename->{destfile}, $config{srcdir});

	if ($config{rcs}) {
		IkiWiki::rcs_rename($rename->{srcfile}, $rename->{destfile});
	}
	else {
		if (! rename($config{srcdir}."/".$rename->{srcfile},
		             $config{srcdir}."/".$rename->{destfile})) {
			error("rename: $!");
		}
	}

}

sub fixlinks ($$$) {
	my $rename=shift;
	my $session=shift;

	my @fixedlinks;

	foreach my $page (keys %links) {
		my $needfix=0;
		foreach my $link (@{$links{$page}}) {
			my $bestlink=bestlink($page, $link);
			if ($bestlink eq $rename->{src}) {
				$needfix=1;
				last;
			}
		}
		if ($needfix) {
			my $file=$pagesources{$page};
			my $oldcontent=readfile($config{srcdir}."/".$file);
			my $content=renamepage_hook($page, $rename->{src}, $rename->{dest}, $oldcontent);
			if ($oldcontent ne $content) {
				my $token=IkiWiki::rcs_prepedit($file);
				eval { writefile($file, $config{srcdir}, $content) };
				next if $@;
				my $conflict=IkiWiki::rcs_commit(
					$file,
					sprintf(gettext("update for rename of %s to %s"), $rename->{srcfile}, $rename->{destfile}),
					$token,
					$session->param("name"), 
					$ENV{REMOTE_ADDR}
				);
				push @fixedlinks, $page if ! defined $conflict;
			}
		}
	}

	return @fixedlinks;
}

1
