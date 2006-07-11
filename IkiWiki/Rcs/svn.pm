#!/usr/bin/perl
# For subversion support.

use warnings;
use strict;
use IkiWiki;

package IkiWiki;
		
my $svn_webcommit=qr/^web commit by (\w+):?(.*)/;

sub svn_info ($$) { #{{{
	my $field=shift;
	my $file=shift;

	my $info=`LANG=C svn info $file`;
	my ($ret)=$info=~/^$field: (.*)$/m;
	return $ret;
} #}}}

sub rcs_update () { #{{{
	if (-d "$config{srcdir}/.svn") {
		if (system("svn", "update", "--quiet", $config{srcdir}) != 0) {
			warn("svn update failed\n");
		}
	}
} #}}}

sub rcs_prepedit ($) { #{{{
	# Prepares to edit a file under revision control. Returns a token
	# that must be passed into rcs_commit when the file is ready
	# for committing.
	# The file is relative to the srcdir.
	my $file=shift;
	
	if (-d "$config{srcdir}/.svn") {
		# For subversion, return the revision of the file when
		# editing begins.
		my $rev=svn_info("Revision", "$config{srcdir}/$file");
		return defined $rev ? $rev : "";
	}
} #}}}

sub rcs_commit ($$$) { #{{{
	# Tries to commit the page; returns undef on _success_ and
	# a version of the page with the rcs's conflict markers on failure.
	# The file is relative to the srcdir.
	my $file=shift;
	my $message=shift;
	my $rcstoken=shift;

	if (-d "$config{srcdir}/.svn") {
		# Check to see if the page has been changed by someone
		# else since rcs_prepedit was called.
		my ($oldrev)=$rcstoken=~/^([0-9]+)$/; # untaint
		my $rev=svn_info("Revision", "$config{srcdir}/$file");
		if (defined $rev && defined $oldrev && $rev != $oldrev) {
			# Merge their changes into the file that we've
			# changed.
			chdir($config{srcdir}); # svn merge wants to be here
			if (system("svn", "merge", "--quiet", "-r$oldrev:$rev",
			           "$config{srcdir}/$file") != 0) {
				warn("svn merge -r$oldrev:$rev failed\n");
			}
		}

		if (system("svn", "commit", "--quiet", 
		           "--encoding", "UTF-8", "-m",
		           possibly_foolish_untaint($message),
			   "$config{srcdir}") != 0) {
			my $conflict=readfile("$config{srcdir}/$file");
			if (system("svn", "revert", "--quiet", "$config{srcdir}/$file") != 0) {
				warn("svn revert failed\n");
			}
			return $conflict;
		}
	}
	return undef # success
} #}}}

sub rcs_add ($) { #{{{
	# filename is relative to the root of the srcdir
	my $file=shift;

	if (-d "$config{srcdir}/.svn") {
		my $parent=dirname($file);
		while (! -d "$config{srcdir}/$parent/.svn") {
			$file=$parent;
			$parent=dirname($file);
		}
		
		if (system("svn", "add", "--quiet", "$config{srcdir}/$file") != 0) {
			warn("svn add failed\n");
		}
	}
} #}}}

sub rcs_recentchanges ($) { #{{{
	my $num=shift;
	my @ret;
	
	return unless -d "$config{srcdir}/.svn";

	eval q{use CGI 'escapeHTML'};
	eval q{use Date::Parse};
	eval q{use Time::Duration};
	eval q{use XML::SAX};
	eval q{use XML::Simple};

	# avoid using XML::SAX::PurePerl, it's buggy with UTF-8 data
	my @parsers = map { ${$_}{Name} } @{XML::SAX->parsers()};
	do {
		$XML::Simple::PREFERRED_PARSER = pop @parsers;
	} until $XML::Simple::PREFERRED_PARSER ne 'XML::SAX::PurePerl';

	# --limit is only supported on Subversion 1.2.0+
	my $svn_version=`svn --version -q`;
	my $svn_limit='';
	$svn_limit="--limit $num"
		if $svn_version =~ /\d\.(\d)\.\d/ && $1 >= 2;

	my $svn_url=svn_info("URL", $config{srcdir});
	my $xml = XMLin(scalar `svn $svn_limit --xml -v log '$svn_url'`,
		ForceArray => [ 'logentry', 'path' ],
		GroupTags => { paths => 'path' },
		KeyAttr => { path => 'content' },
	);
	foreach my $logentry (@{$xml->{logentry}}) {
		my (@pages, @message);

		my $rev = $logentry->{revision};
		my $user = $logentry->{author};

		my $date = $logentry->{date};
		$date =~ s/T/ /;
		$date =~ s/\.\d+Z$//;
		my $when=concise(ago(time - str2time($date, 'UTC')));

		foreach my $msgline (split(/\n/, $logentry->{msg})) {
			push @message, { line => escapeHTML($msgline) };
		}

		my $committype="web";
		if (defined $message[0] &&
		    $message[0]->{line}=~/$svn_webcommit/) {
			$user="$1";
			$message[0]->{line}=$2;
		}
		else {
			$committype="svn";
		}

		foreach (keys %{$logentry->{paths}}) {
			next unless /^\/\Q$config{svnpath}\E\/([^ ]+)(?:$|\s)/;
			my $file=$1;
			my $diffurl=$config{diffurl};
			$diffurl=~s/\[\[file\]\]/$file/g;
			$diffurl=~s/\[\[r1\]\]/$rev - 1/eg;
			$diffurl=~s/\[\[r2\]\]/$rev/g;
			push @pages, {
				link => htmllink("", "", pagename($file), 1),
				diffurl => $diffurl,
			} if length $file;
		}
		push @ret, { rev => $rev,
			user => htmllink("", "", $user, 1),
			committype => $committype,
			when => $when,
			message => [@message],
			pages => [@pages],
		} if @pages;
		return @ret if @ret >= $num;
	}

	return @ret;
} #}}}

sub rcs_notify () { #{{{
	if (! exists $ENV{REV}) {
		error("REV is not set, not running from svn post-commit hook, cannot send notifications");
	}
	my $rev=int(possibly_foolish_untaint($ENV{REV}));
	
	my $user=`svnlook author $config{svnrepo} -r $rev`;
	chomp $user;
	my $message=`svnlook log $config{svnrepo} -r $rev`;
	if ($message=~/$svn_webcommit/) {
		$user="$1";
		$message=$2;
	}

	my @changed_pages;
	foreach my $change (`svnlook changed $config{svnrepo} -r $rev`) {
		chomp $change;
		if ($change =~ /^[A-Z]+\s+\Q$config{svnpath}\E\/(.*)/) {
			push @changed_pages, $1;
		}
	}
		
	require IkiWiki::UserInfo;
	my @email_recipients=commit_notify_list($user, @changed_pages);
	if (@email_recipients) {
		# TODO: if a commit spans multiple pages, this will send
		# subscribers a diff that might contain pages they did not
		# sign up for. Should separate the diff per page and
		# reassemble into one mail with just the pages subscribed to.
		my $diff=`svnlook diff $config{svnrepo} -r $rev --no-diff-deleted`;

		my $subject="$config{wikiname} update of ";
		if (@changed_pages > 2) {
			$subject.="$changed_pages[0] $changed_pages[1] etc";
		}
		else {
			$subject.=join(" ", @changed_pages);
		}
		$subject.=" by $user";

		my $template=template("notifymail.tmpl");
		$template->param(
			wikiname => $config{wikiname},
			diff => $diff,
			user => $user,
			message => $message,
		);
		
		eval q{use Mail::Sendmail};
		foreach my $email (@email_recipients) {
			sendmail(
				To => $email,
				From => "$config{wikiname} <$config{adminemail}>",
				Subject => $subject,
				Message => $template->output,
			) or error("Failed to send update notification mail");
		}
	}
} #}}}

sub rcs_getctime ($) { #{{{
	my $file=shift;
	eval q{use Date::Parse};

	my $svn_log_infoline=qr/^r\d+\s+\|\s+[^\s]+\s+\|\s+(\d+-\d+-\d+\s+\d+:\d+:\d+\s+[-+]?\d+).*/;
		
	my $child = open(SVNLOG, "-|");
	if (! $child) {
		exec("svn", "log", $file) || error("svn log $file failed to run");
	}

	my $date;
	while (<SVNLOG>) {
		if (/$svn_log_infoline/) {
			$date=$1;
	    	}
	}
	close SVNLOG || warn "svn log $file exited $?";

	if (! defined $date) {
		warn "failed to parse svn log for $file\n";
		return 0;
	}
		
	$date=str2time($date);
	debug("found ctime ".localtime($date)." for $file");
	return $date;
} #}}}

1
