#!/usr/bin/perl
# outline markup
package IkiWiki::Plugin::otl;

use warnings;
use strict;
use IkiWiki 3.00;
use open qw{:utf8 :std};

sub import {
	hook(type => "getsetup", id => "otl", call => \&getsetup);
	hook(type => "filter", id => "otl", call => \&filter);
	hook(type => "htmlize", id => "otl", call => \&htmlize);

}

sub getsetup () {
	return 
		plugin => {
			safe => 1,
			rebuild => 1, # format plugin
		},
}

sub filter (@) {
	my %params=@_;
        
	# Munge up check boxes to look a little bit better. This is a hack.
	my $checked=htmllink($params{page}, $params{page},
		"smileys/star_on.png", linktext => "[X]");
	my $unchecked=htmllink($params{page}, $params{page},
		"smileys/star_off.png", linktext => "[_]");
	$params{content}=~s/^(\s*)\[X\]\s/${1}$checked /mg;
	$params{content}=~s/^(\s*)\[_\]\s/${1}$unchecked /mg;
        
	return $params{content};
}

sub htmlize (@) {
	my %params=@_;

	# Can't use open2 since otl2html doesn't play nice with buffering.
	# Instead, fork off a child process that will run otl2html and feed
	# it the content. Then read otl2html's response.

	my $tries=10;
	my $pid;
	do {
		$pid = open(KID_TO_READ, "-|");
		unless (defined $pid) {
			$tries--;
			if ($tries < 1) {
				debug("failed to fork: $@");
				return $params{content};
			}
		}
	} until defined $pid;

	if (! $pid) {
		$tries=10;
		$pid=undef;

		do {
			$pid = open(KID_TO_WRITE, "|-");
			unless (defined $pid) {
				$tries--;
				if ($tries < 1) {
					debug("failed to fork: $@");
					print $params{content};
					exit;
				}
			}
		} until defined $pid;

		if (! $pid) {
			if (! exec 'otl2html', '-S', '/dev/null', '-T', '/dev/stdin') {
				debug("failed to run otl2html: $@");
				print $params{content};
				exit;
			}
		}

		print KID_TO_WRITE $params{content};
		close KID_TO_WRITE;
		waitpid $pid, 0;
		exit;
	}
	
	local $/ = undef;
	my $ret=<KID_TO_READ>;
	close KID_TO_READ;
	waitpid $pid, 0;

	$ret=~s/.*<body>//s;
	$ret=~s/<body>.*//s;
	$ret=~s/<div class="Footer">.*//s;
	return $ret;
}

1
