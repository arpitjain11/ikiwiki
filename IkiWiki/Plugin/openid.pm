#!/usr/bin/perl
# OpenID support.
package IkiWiki::Plugin::openid;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	hook(type => "getopt", id => "openid", call => \&getopt);
	hook(type => "auth", id => "openid", call => \&auth);
	hook(type => "formbuilder_setup", id => "openid",
		call => \&formbuilder_setup, last => 1);
} # }}}

sub getopt () { #{{{
	eval q{use Getopt::Long};
	error($@) if $@;
	Getopt::Long::Configure('pass_through');
	GetOptions("openidsignup=s" => \$config{openidsignup});
} #}}}

sub formbuilder_setup (@) { #{{{
	my %params=@_;

	my $form=$params{form};
	my $session=$params{session};
	my $cgi=$params{cgi};

	if ($form->title eq "signin") {
 		$form->field(
			name => "openid_url",
			label => "OpenID",
			size => 30,
			comment => '('.
				htmllink("", "", "OpenID", 1, 0, "What's this?")
				.($config{openidsignup} ? " | <a href=\"$config{openidsignup}\">Get an OpenID</a>" : "")
				.')'
		);

		# Handle submission of an OpenID as validation.
		if ($form->submitted && $form->submitted eq "Login" &&
		    defined $form->field("openid_url") && 
		    length $form->field("openid_url")) {
			$form->field(
				name => "openid_url",
				validate => sub {
					validate($cgi, $session, shift, $form);
				},
			);
			# Skip all other required fields in this case.
			foreach my $field ($form->field) {
				next if $field eq "openid_url";
				$form->field(name => $field, required => 0,
					validate => '/.*/');
			}
		}
	}
}

sub validate ($$$;$) { #{{{
	my $q=shift;
	my $session=shift;
	my $openid_url=shift;
	my $form=shift;

	my $csr=getobj($q, $session);

	my $claimed_identity = $csr->claimed_identity($openid_url);
	if (! $claimed_identity) {
		if ($form) {
			# Put the error in the form and fail validation.
			$form->field(name => "openid_url", comment => $csr->err);
			return 0;
		}
		else {
			error($csr->err);
		}
	}

	my $check_url = $claimed_identity->check_url(
		return_to => IkiWiki::cgiurl(do => "postsignin"),
		trust_root => $config{cgiurl},
		delayed_return => 1,
	);
	# Redirect the user to the OpenID server, which will
	# eventually bounce them back to auth()
	IkiWiki::redirect($q, $check_url);
	exit 0;
} #}}}

sub auth ($$) { #{{{
	my $q=shift;
	my $session=shift;

	if (defined $q->param('openid.mode')) {
		my $csr=getobj($q, $session);

		if (my $setup_url = $csr->user_setup_url) {
			IkiWiki::redirect($q, $setup_url);
		}
		elsif ($csr->user_cancel) {
			IkiWiki::redirect($q, $config{url});
		}
		elsif (my $vident = $csr->verified_identity) {
			$session->param(name => $vident->url);
		}
		else {
			error("OpenID failure: ".$csr->err);
		}
	}
	elsif (defined $q->param('openid_identifier')) {
		# myopenid.com affiliate support
		validate($q, $session, $q->param('openid_identifier'));
	}
} #}}}

sub getobj ($$) { #{{{
	my $q=shift;
	my $session=shift;

	eval q{use Net::OpenID::Consumer};
	error($@) if $@;

	my $ua;
	eval q{use LWPx::ParanoidAgent};
	if (! $@) {
		$ua=LWPx::ParanoidAgent->new;
	}
	else {
	        $ua=LWP::UserAgent->new;
	}

	# Store the secret in the session.
	my $secret=$session->param("openid_secret");
	if (! defined $secret) {
		$secret=$session->param(openid_secret => time);
	}

	return Net::OpenID::Consumer->new(
		ua => $ua,
		args => $q,
		consumer_secret => $secret,
		required_root => $config{cgiurl},
	);
} #}}}

1
