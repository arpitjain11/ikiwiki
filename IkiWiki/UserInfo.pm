#!/usr/bin/perl

use warnings;
use strict;
use Storable;
use IkiWiki;

package IkiWiki;

sub userinfo_retrieve () { #{{{
	my $userinfo=eval{ Storable::lock_retrieve("$config{wikistatedir}/userdb") };
	return $userinfo;
} #}}}
	
sub userinfo_store ($) { #{{{
	my $userinfo=shift;
	
	my $oldmask=umask(077);
	my $ret=Storable::lock_store($userinfo, "$config{wikistatedir}/userdb");
	umask($oldmask);
	return $ret;
} #}}}
	
sub userinfo_get ($$) { #{{{
	my $user=shift;
	my $field=shift;

	my $userinfo=userinfo_retrieve();
	if (! defined $userinfo ||
	    ! exists $userinfo->{$user} || ! ref $userinfo->{$user} ||
            ! exists $userinfo->{$user}->{$field}) {
		return "";
	}
	return $userinfo->{$user}->{$field};
} #}}}

sub userinfo_set ($$$) { #{{{
	my $user=shift;
	my $field=shift;
	my $value=shift;
	
	my $userinfo=userinfo_retrieve();
	if (! defined $userinfo ||
	    ! exists $userinfo->{$user} || ! ref $userinfo->{$user}) {
		return "";
	}
	
	$userinfo->{$user}->{$field}=$value;
	return userinfo_store($userinfo);
} #}}}

sub userinfo_setall ($$) { #{{{
	my $user=shift;
	my $info=shift;
	
	my $userinfo=userinfo_retrieve();
	if (! defined $userinfo) {
		$userinfo={};
	}
	$userinfo->{$user}=$info;
	return userinfo_store($userinfo);
} #}}}

sub is_admin ($) { #{{{
	my $user_name=shift;

	return grep { $_ eq $user_name } @{$config{adminuser}};
} #}}}

sub get_banned_users () { #{{{
	my @ret;
	my $userinfo=userinfo_retrieve();
	foreach my $user (keys %{$userinfo}) {
		push @ret, $user if $userinfo->{$user}->{banned};
	}
	return @ret;
} #}}}

sub set_banned_users (@) { #{{{
	my %banned=map { $_ => 1 } @_;
	my $userinfo=userinfo_retrieve();
	foreach my $user (keys %{$userinfo}) {
		$userinfo->{$user}->{banned} = $banned{$user};
	}
	return userinfo_store($userinfo);
} #}}}

sub commit_notify_list ($@) { #{{{
	my $committer=shift;
	
	my @pages;
	foreach my $file (@_) {
		push @pages, grep { $pagesources{$_} eq $file } keys %pagesources;
	}
	
	my @ret;
	my $userinfo=userinfo_retrieve();
	foreach my $user (keys %{$userinfo}) {
		next if $user eq $committer;
		if (exists $userinfo->{$user}->{subscriptions} &&
		    length $userinfo->{$user}->{subscriptions} &&
		    exists $userinfo->{$user}->{email} &&
		    length $userinfo->{$user}->{email} &&
		    grep { pagespec_match($_, $userinfo->{$user}->{subscriptions}) } @pages) {
			push @ret, $userinfo->{$user}->{email};
		}
	}
	return @ret;
} #}}}

sub send_commit_mails ($$$@) { #{{{
	my $messagesub=shift;
	my $diffsub=shift;
	my $user=shift;
	my @changed_pages=@_;

	return unless @changed_pages;

	my @email_recipients=commit_notify_list($user, @changed_pages);
	if (@email_recipients) {
		# TODO: if a commit spans multiple pages, this will send
		# subscribers a diff that might contain pages they did not
		# sign up for. Should separate the diff per page and
		# reassemble into one mail with just the pages subscribed to.
		my $diff=$diffsub->();
		my $message=$messagesub->();

		my $pagelist;
		if (@changed_pages > 2) {
			$pagelist="$changed_pages[0] $changed_pages[1] ...";
		}
		else {
			$pagelist.=join(" ", @changed_pages);
		}
		#translators: The three variables are the name of the wiki,
		#translators: A list of one or more pages that were changed,
		#translators: And the name of the user making the change.
		#translators: This is used as the subject of a commit email.
		my $subject=sprintf(gettext("update of %s's %s by %s"), 
			$config{wikiname}, $pagelist, $user);

		my $template=template("notifymail.tmpl");
		$template->param(
			wikiname => $config{wikiname},
			diff => $diff,
			user => $user,
			message => $message,
		);

		# Daemonize, in case the mail sending takes a while.
		defined(my $pid = fork) or error("Can't fork: $!");
		return if $pid;
		setsid() or error("Can't start a new session: $!");
		eval q{use POSIX 'setsid'};
		chdir '/';
		open STDIN, '/dev/null';
		open STDOUT, '>/dev/null';
		open STDERR, '>&STDOUT' or error("Can't dup stdout: $!");

		unlockwiki(); # don't need to keep a lock on the wiki

		eval q{use Mail::Sendmail};
		error($@) if $@;
		foreach my $email (@email_recipients) {
			sendmail(
				To => $email,
				From => "$config{wikiname} <$config{adminemail}>",
				Subject => $subject,
				Message => $template->output,
			);
		}

		exit 0; # daemon process done
	}
} #}}}

1
