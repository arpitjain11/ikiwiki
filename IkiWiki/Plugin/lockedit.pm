#!/usr/bin/perl
package IkiWiki::Plugin::lockedit;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "getsetup", id => "lockedit", call => \&getsetup);
	hook(type => "canedit", id => "lockedit", call => \&canedit);
	hook(type => "formbuilder_setup", id => "lockedit",
	     call => \&formbuilder_setup);
} # }}}

sub getsetup () { #{{{
	return
		plugin => {
			safe => 1,
			rebuild => 0,
		},
		locked_pages => {
			type => "pagespec",
			example => "!*/Discussion",
			description => "PageSpec controlling which pages are locked",
			link => "ikiwiki/PageSpec",
			safe => 1,
			rebuild => 0,
		},
} #}}}

sub canedit ($$) { #{{{
	my $page=shift;
	my $cgi=shift;
	my $session=shift;

	my $user=$session->param("name");
	return undef if defined $user && IkiWiki::is_admin($user);

	if (defined $config{locked_pages} && length $config{locked_pages} &&
	    pagespec_match($page, $config{locked_pages})) {
		if (! defined $user ||
		    ! IkiWiki::userinfo_get($session->param("name"), "regdate")) {
			return sub { IkiWiki::needsignin($cgi, $session) };
		}
		else {
			return sprintf(gettext("%s is locked and cannot be edited"),
				htmllink("", "", $page, noimageinline => 1));
			
		}
	}

	# XXX deprecated, should be removed eventually
	foreach my $admin (@{$config{adminuser}}) {
		if (pagespec_match($page, IkiWiki::userinfo_get($admin, "locked_pages"))) {
			if (! defined $user ||
			    ! IkiWiki::userinfo_get($session->param("name"), "regdate")) {
				return sub { IkiWiki::needsignin($cgi, $session) };
			}
			else {
				return sprintf(gettext("%s is locked and cannot be edited"),
					htmllink("", "", $page, noimageinline => 1));
			}
		}
	}

	return undef;
} #}}}

sub formbuilder_setup (@) { #{{{
	my %params=@_;

	# XXX deprecated, should be removed eventually	
	my $form=$params{form};
	if ($form->title eq "preferences") {
		my $session=$params{session};
		my $cgi=$params{cgi};
		my $user_name=$session->param("name");

		$form->field(name => "locked_pages", size => 50,
			fieldset => "admin",
			comment => "deprecated; please move to locked_pages in setup file"
		);
		if (! IkiWiki::is_admin($user_name)) {
			$form->field(name => "locked_pages", type => "hidden");
		}
		if (! $form->submitted) {
			my $value=IkiWiki::userinfo_get($user_name, "locked_pages");
			if (length $value) {
				$form->field(name => "locked_pages", force => 1, value => $value);
			}
			else {
				$form->field(name => "locked_pages", type => "hidden");
			}
		}
		if ($form->submitted && $form->submitted eq 'Save Preferences') {
			if (defined $form->field("locked_pages")) {
				IkiWiki::userinfo_set($user_name, "locked_pages",
					$form->field("locked_pages")) ||
						error("failed to set locked_pages");
				if (! length $form->field("locked_pages")) {
					$form->field(name => "locked_pages", type => "hidden");
				}
			}
		}
	}
} #}}}

1
