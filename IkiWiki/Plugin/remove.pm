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
		push @{$params{buttons}}, "Remove";
		# TODO button for attachments
	}
} #}}}

sub confirmation_form ($$) { #{{{ 
	my $q=shift;
	my $session=shift;

	eval q{use CGI::FormBuilder};
	error($@) if $@;
	my @fields=qw(do page);
	my $f = CGI::FormBuilder->new(
		title => "confirm removal",
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
	$f->field(name => "page", label => "Will remove:", validate => sub {
		my $page=shift;
		if (! exists $pagesources{$page}) {
			$f->field(name => "page", message => gettext("page does not exist"));
			return 0;
		}
		else {
			IkiWiki::check_canedit($page, $q, $session);
			return 1;
		}
	});

	return $f, ["Remove", "Cancel"];
} #}}}

sub formbuilder (@) { #{{{
	my %params=@_;
	my $form=$params{form};

	if (defined $form->field("do") && $form->field("do") eq "edit" &&
	    $form->submitted eq "Remove") {
		# When the remove button is pressed on the edit form,
		# save the rest of the form state and generate a small
		# remove confirmation form.

		# TODO save state


		my $q=$params{cgi};
		my $session=$params{session};
		my ($f, $buttons)=confirmation_form($q, $session);
		$f->field(name => "page", value => $form->field("page"),
			force => 1);
		IkiWiki::showform($f, $buttons, $session, $q);
		exit 0;
	}
} #}}}

sub sessioncgi ($$) { #{{{
        my $q=shift;

	if ($q->param("do") eq 'remove') {
        	my $session=shift;
		my ($form, $buttons)=confirmation_form($q, $session);
		IkiWiki::decode_form_utf8($form);
		if ($form->submitted eq 'Cancel') {
			error("canceled"); # TODO load state
		}
		elsif ($form->submitted eq 'Remove' && $form->validate) {
			error("removal not yet implemented"); # TODO
		}
		else {
			IkiWiki::showform($form, $buttons, $session, $q);
			exit 0;
		}
	}
}

1
