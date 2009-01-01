#!/usr/bin/perl

package IkiWiki;

use warnings;
use strict;
use Storable;
use IkiWiki;

sub userinfo_retrieve () {
	my $userinfo=eval{ Storable::lock_retrieve("$config{wikistatedir}/userdb") };
	return $userinfo;
}

sub userinfo_store ($) {
	my $userinfo=shift;
	
	my $newfile="$config{wikistatedir}/userdb.new";
	my $oldmask=umask(077);
	my $ret=Storable::lock_nstore($userinfo, $newfile);
	umask($oldmask);
	if (defined $ret && $ret) {
		if (! rename($newfile, "$config{wikistatedir}/userdb")) {
			unlink($newfile);
			$ret=undef;
		}
	}
	return $ret;
}

sub userinfo_get ($$) {
	my $user=shift;
	my $field=shift;

	my $userinfo=userinfo_retrieve();
	if (! defined $userinfo ||
	    ! exists $userinfo->{$user} || ! ref $userinfo->{$user} ||
            ! exists $userinfo->{$user}->{$field}) {
		return "";
	}
	return $userinfo->{$user}->{$field};
}

sub userinfo_set ($$$) {
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
}

sub userinfo_setall ($$) {
	my $user=shift;
	my $info=shift;
	
	my $userinfo=userinfo_retrieve();
	if (! defined $userinfo) {
		$userinfo={};
	}
	$userinfo->{$user}=$info;
	return userinfo_store($userinfo);
}

sub is_admin ($) {
	my $user_name=shift;

	return grep { $_ eq $user_name } @{$config{adminuser}};
}

1
