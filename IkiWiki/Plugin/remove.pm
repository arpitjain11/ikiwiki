#!/usr/bin/perl
package IkiWiki::Plugin::remove;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "formbuilder_setup", id => "remove", call => \&formbuilder_setup);
	hook(type => "formbuilder", id => "remove", call => \&formbuilder);
	hook(type => "sessioncgi", id => "remove", call => \&sessioncgi);

} # }}}

sub formbuilder_setup (@) { #{{{
	my %params=@_;
	my $form=$params{form};
	my $q=$params{cgi};

	if (defined $form->field("do") && $form->field("do") eq "edit") {
		# Removal button for the page, and also for attachments.
		push @{$params{buttons}}, "Remove";
		$form->tmpl_param("field-remove" => '<input name="_submit" type="submit" value="Remove Attachments" />');
	}
} #}}}

sub confirmation_form ($$$) { #{{{ 
	my $q=shift;
	my $session=shift;
	my $page=shift;

	eval q{use CGI::FormBuilder};
	error($@) if $@;
	my @fields=qw(do page);
	my $f = CGI::FormBuilder->new(
		title => sprintf(gettext("confirm removal of %s"),
			IkiWiki::pagetitle($page)),
		name => "remove",
		header => 0,
		charset => "utf-8",
		method => 'POST',
		javascript => 0,
		params => $q,
		action => $config{cgiurl},
		stylesheet => IkiWiki::baseurl()."style.css",
		fields => \@fields,
	);
	
	$f->field(name => "do", type => "hidden", value => "remove", force => 1);
	$f->field(name => "page", type => "hidden", value => $page, force => 1);

	return $f, ["Remove", "Cancel"];
} #}}}

sub formbuilder (@) { #{{{
	my %params=@_;
	my $form=$params{form};

	if (defined $form->field("do") && $form->field("do") eq "edit") {
		if ($form->submitted eq "Remove") {
			my $q=$params{cgi};
			my $session=$params{session};

		    	# Save current form state to allow returning to it later
			# without losing any edits.
			# (But don't save what button was submitted, to avoid
			# looping back to here.)
			# Note: "_submit" is CGI::FormBuilder internals.
			$q->param(-name => "_submit", -value => "");
			$session->param(postremove => scalar $q->Vars);
			IkiWiki::cgi_savesession($session);
	
			# Display a small confirmation form.
			my ($f, $buttons)=confirmation_form($q, $session, $form->field("page"));
			IkiWiki::showform($f, $buttons, $session, $q);
			exit 0;
		}
		elsif ($form->submitted eq "Remove Attachments") {
			
		}
	}
} #}}}

sub sessioncgi ($$) { #{{{
        my $q=shift;

	if ($q->param("do") eq 'remove') {
        	my $session=shift;
		my ($form, $buttons)=confirmation_form($q, $session, $session->param("page"));
		IkiWiki::decode_form_utf8($form);

		if ($form->submitted eq 'Cancel') {
			# Load saved form state and return to edit form.
			my $postremove=CGI->new($session->param("postremove"));
			$session->clear("postremove");
			IkiWiki::cgi_savesession($session);
			IkiWiki::cgi($postremove, $session);
		}
		elsif ($form->submitted eq 'Remove' && $form->validate) {
			my $page=$form->field("page");
			my $file=$pagesources{$page};
	
			# Validate removal by checking that the page exists,
			# and that the user is allowed to edit(/remove) it.
			if (! exists $pagesources{$page}) {
				error(sprintf(gettext("%s does not exist"),
				htmllink("", "", $page, noimageinline => 1)));
			}
			IkiWiki::check_canedit($page, $q, $session);

			# Do removal, and update the wiki.
			require IkiWiki::Render;
			if ($config{rcs}) {
				IkiWiki::rcs_remove($file);
				IkiWiki::disable_commit_hook();
				IkiWiki::rcs_commit($file, gettext("removed"),
					IkiWiki::rcs_prepedit($file),
					$session->param("name"), $ENV{REMOTE_ADDR});
				IkiWiki::enable_commit_hook();
				IkiWiki::rcs_update();
			}
			IkiWiki::prune("$config{srcdir}/$file");
			IkiWiki::refresh();
			IkiWiki::saveindex();

			# Redirect to parent of the page.
			my $parent=IkiWiki::dirname($page);
			if (! exists $pagesources{$parent}) {
				$parent="index";
			}
			IkiWiki::redirect($q, $config{url}."/".htmlpage($parent));
		}
		else {
			IkiWiki::showform($form, $buttons, $session, $q);
		}

		exit 0;
	}
}

1
