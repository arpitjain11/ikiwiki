#!/usr/bin/perl
# Munge a git log into log for code_swarm.
# Deals with oddities of ikiwiki commits, like web commits, and openids.
use IkiWiki;
use IkiWiki::Plugin::openid;

my $sep='-' x 72;
$/=$sep."\n";

my %config=IkiWiki::defaultconfig();

foreach (`git-log --name-status --pretty=format:'%n$sep%nr%h | %an | %ai (%aD) | x lines%n%nsubject: %s%n'`) {
	my ($subject)=m/subject: (.*)\n/m;
	if ($subject=~m/$config{web_commit_regexp}/) {
		my $user = defined $2 ? "$2" : "$3";
		my $oiduser = IkiWiki::openiduser($user);
		if (defined $oiduser) {
			$oiduser=~s/ \[.*\]//; # too much clutter for code_swarm
			$user=$oiduser;
		}
		s/ \| [^|]+ \| / | $user | /;
	}
	s/subject: (.*)\n\n//m;
	print;
}
