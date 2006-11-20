#!/usr/bin/perl
# OpenID support.
package IkiWiki::Plugin::openid;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	hook(type => "checkconfig", id => "smiley", call => \&checkconfig);
	hook(type => "auth", id => "skeleton", call => \&auth);
} # }}}

sub checkconfig () { #{{{
	# Currently part of the OpenID code is in CGI.pm, and is enabled by
	# this setting.
	# TODO: modularise it all out into this plugin..
	$config{openid}=1;
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
	}
} #}}}

sub validate ($$$$) { #{{{
	my $q=shift;
	my $session=shift;
	my $form=shift;
	my $openid_url=shift;

	my $csr=getobj($q, $session);

	my $claimed_identity = $csr->claimed_identity($openid_url);
	if (! $claimed_identity) {
		# Put the error in the form and fail validation.
		$form->field(name => "openid_url", comment => $csr->err);
		return 0;
	}
	my $check_url = $claimed_identity->check_url(
		return_to => IkiWiki::cgiurl(
			do => $form->field("do"),
			page => $form->field("page"),
			title => $form->field("title"),
			from => $form->field("from"),
			subpage => $form->field("subpage")
		),
		trust_root => $config{cgiurl},
		delayed_return => 1,
	);
	# Redirect the user to the OpenID server, which will
	# eventually bounce them back to auth() above.
	IkiWiki::redirect($q, $check_url);
	exit 0;
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
