#!/usr/bin/perl
package IkiWiki::Plugin::websetup;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "sessioncgi", id => "websetup",
	     call => \&sessioncgi);
	hook(type => "formbuilder_setup", id => "websetup",
	     call => \&formbuilder_setup);
} # }}}

sub showform ($$) { #{{{
	my $cgi=shift;
	my $session=shift;

	if (! defined $session->param("name") || 
	    ! IkiWiki::is_admin($session->param("name"))) {
		error(gettext("you are not logged in as an admin"));
	}

	eval q{use CGI::FormBuilder};
	error($@) if $@;

	my $form = CGI::FormBuilder->new(
		title => "setup",
		name => "setup",
		header => 0,
		charset => "utf-8",
		method => 'POST',
		params => $cgi,
		action => $config{cgiurl},
		template => {type => 'div'},
		stylesheet => IkiWiki::baseurl()."style.css",
	);
	my $buttons=["Save Setup", "Cancel"];

	IkiWiki::decode_form_utf8($form);
	IkiWiki::run_hooks(formbuilder_setup => sub {
		shift->(form => $form, cgi => $cgi, session => $session,
			buttons => $buttons);
	});
	IkiWiki::decode_form_utf8($form);

	$form->field(name => "do", type => "hidden", value => "setup",
		force => 1);

	if (! $form->submitted) {
		# TODO
	}

	if ($form->submitted eq "Cancel") {
		IkiWiki::redirect($cgi, $config{url});
		return;
	}
	elsif ($form->submitted eq 'Save Setup' && $form->validate) {
		# TODO

		$form->text(gettext("Setup saved."));
	}

	IkiWiki::showform($form, $buttons, $session, $cgi);
} #}}}

sub sessioncgi ($$) { #{{{
	my $cgi=shift;
	my $session=shift;

	if ($cgi->param("do") eq "setup") {
		showform($cgi, $session);
		exit;
	}
} #}}}

sub formbuilder_setup (@) { #{{{
	my %params=@_;

	my $form=$params{form};
	if ($form->title eq "preferences") {
		push @{$params{buttons}}, "Wiki Setup";
		if ($form->submitted && $form->submitted eq "Wiki Setup") {
			showform($params{cgi}, $params{session});
			exit;
		}
	}
} #}}}

1
