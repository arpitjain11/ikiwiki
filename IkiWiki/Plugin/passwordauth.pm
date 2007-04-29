#!/usr/bin/perl
# Ikiwiki password authentication.
package IkiWiki::Plugin::passwordauth;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
        hook(type => "formbuilder_setup", id => "passwordauth",
		call => \&formbuilder_setup);
        hook(type => "formbuilder", id => "passwordauth",
		call => \&formbuilder);
} # }}}

sub formbuilder_setup (@) { #{{{
	my %params=@_;

	my $form=$params{form};
	my $session=$params{session};
	my $cgi=$params{cgi};

	if ($form->title eq "signin" || $form->title eq "register") {
		$form->field(name => "name", required => 0, size => 50);
		$form->field(name => "password", type => "password", required => 0);
		
		if ($form->submitted eq "Register" || $form->submitted eq "Create Account") {
			$form->field(name => "confirm_password", type => "password");
			$form->field(name => "email", size => 50);
			$form->title("register");
			$form->text("");
		}

		if ($form->submitted) {
			my $submittype=$form->submitted;
			# Set required fields based on how form was submitted.
			my %required=(
				"Login" => [qw(name password)],
				"Register" => [],
				"Create Account" => [qw(name password confirm_password email)],
				"Mail Password" => [qw(name)],
			);
			foreach my $opt (@{$required{$submittype}}) {
				$form->field(name => $opt, required => 1);
			}
	
			if ($submittype eq "Create Account") {
				$form->field(
					name => "confirm_password",
					validate => sub {
						shift eq $form->field("password");
					},
				);
				$form->field(
					name => "email",
					validate => "EMAIL",
				);
			}

			# Validate password against name for Login.
			if ($submittype eq "Login") {
				$form->field(
					name => "password",
					validate => sub {
						length $form->field("name") &&
						shift eq IkiWiki::userinfo_get($form->field("name"), 'password');
					},
				);
			}
			elsif ($submittype eq "Register" ||
			       $submittype eq "Create Account" ||
			       $submittype eq "Mail Password") {
				$form->field(name => "password", validate => 'VALUE');
			}
			
			# And make sure the entered name exists when logging
			# in or sending email, and does not when registering.
			if ($submittype eq 'Create Account' ||
			    $submittype eq 'Register') {
				$form->field(
					name => "name",
					validate => sub {
						my $name=shift;
						length $name &&
						$name=~/$config{wiki_file_regexp}/ &&
						! IkiWiki::userinfo_get($name, "regdate");
					},
				);
			}
			elsif ($submittype eq "Login" ||
			       $submittype eq "Mail Password") {
				$form->field( 
					name => "name",
					validate => sub {
						my $name=shift;
						length $name &&
						IkiWiki::userinfo_get($name, "regdate");
					},
				);
			}
		}
		else {
			# First time settings.
			$form->field(name => "name", comment => gettext("(use FirstnameLastName)"));
			if ($session->param("name")) {
				$form->field(name => "name", value => $session->param("name"));
			}
		}
	}
	elsif ($form->title eq "preferences") {
		$form->field(name => "name", disabled => 1, 
			value => $session->param("name"), force => 1,
			fieldset => "login");
		$form->field(name => "password", type => "password",
			fieldset => "login");
		$form->field(name => "confirm_password", type => "password",
			fieldset => "login",
			validate => sub {
				shift eq $form->field("password");
			});
		
	}
}

sub formbuilder (@) { #{{{
	my %params=@_;

	my $form=$params{form};
	my $session=$params{session};
	my $cgi=$params{cgi};
	my $buttons=$params{buttons};

	if ($form->title eq "signin" || $form->title eq "register") {
		if ($form->submitted && $form->validate) {
			if ($form->submitted eq 'Login') {
				$session->param("name", $form->field("name"));
				IkiWiki::cgi_postsignin($cgi, $session);
			}
			elsif ($form->submitted eq 'Create Account') {
				my $user_name=$form->field('name');
				if (IkiWiki::userinfo_setall($user_name, {
				    	'email' => $form->field('email'),
					'password' => $form->field('password'),
					'regdate' => time})) {
					$form->field(name => "confirm_password", type => "hidden");
					$form->field(name => "email", type => "hidden");
					$form->text(gettext("Account creation successful. Now you can Login."));
				}
				else {
					error(gettext("Error creating account."));
				}
			}
			elsif ($form->submitted eq 'Mail Password') {
				my $user_name=$form->field("name");
				my $template=template("passwordmail.tmpl");
				$template->param(
					user_name => $user_name,
					user_password => IkiWiki::userinfo_get($user_name, "password"),
					wikiurl => $config{url},
					wikiname => $config{wikiname},
					REMOTE_ADDR => $ENV{REMOTE_ADDR},
				);
			
				eval q{use Mail::Sendmail};
				error($@) if $@;
				sendmail(
					To => IkiWiki::userinfo_get($user_name, "email"),
					From => "$config{wikiname} admin <$config{adminemail}>",
					Subject => "$config{wikiname} information",
					Message => $template->output,
				) or error(gettext("Failed to send mail"));
			
				$form->text(gettext("Your password has been emailed to you."));
				$form->field(name => "name", required => 0);
				push @$buttons, "Mail Password";
			}
			elsif ($form->submitted eq "Register") {
				@$buttons="Create Account";
			}
		}
		elsif ($form->submitted eq "Create Account") {
			@$buttons="Create Account";
		}
		else {
			push @$buttons, "Register", "Mail Password";
		}
	}
	elsif ($form->title eq "preferences") {
		if ($form->submitted eq "Save Preferences" && $form->validate) {
			my $user_name=$form->field('name');
	                foreach my $field (qw(password)) {
        	                if (defined $form->field($field) && length $form->field($field)) {
					IkiWiki::userinfo_set($user_name, $field, $form->field($field)) ||
						error("failed to set $field");
	                        }
	                }
		}
	}
	
	IkiWiki::printheader($session);
	print IkiWiki::misctemplate($form->title, $form->render(submit => $buttons));
} #}}}

1
