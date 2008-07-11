#!/usr/bin/perl

package IkiWiki::Rcs::svn;

use warnings;
use strict;
use IkiWiki;
use POSIX qw(setlocale LC_CTYPE);

sub import { #{{{
	if (exists $IkiWiki::config{svnpath}) {
		# code depends on the path not having extraneous slashes
		$IkiWiki::config{svnpath}=~tr#/#/#s;
		$IkiWiki::config{svnpath}=~s/\/$//;
		$IkiWiki::config{svnpath}=~s/^\///;
	}
} #}}}


package IkiWiki;

# svn needs LC_CTYPE set to a UTF-8 locale, so try to find one. Any will do.
sub find_lc_ctype() {
	my $current = setlocale(LC_CTYPE());
	return $current if $current =~ m/UTF-?8$/i;

	# Make some obvious attempts to avoid calling `locale -a`
	foreach my $locale ("$current.UTF-8", "en_US.UTF-8", "en_GB.UTF-8") {
		return $locale if setlocale(LC_CTYPE(), $locale);
	}

	# Try to get all available locales and pick the first UTF-8 one found.
	if (my @locale = grep(/UTF-?8$/i, `locale -a`)) {
		chomp @locale;
		return $locale[0] if setlocale(LC_CTYPE(), $locale[0]);
	}

	# fallback to the current locale
	return $current;
} # }}}
$ENV{LC_CTYPE} = $ENV{LC_CTYPE} || find_lc_ctype();

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

sub rcs_commit ($$$;$$) { #{{{
	# Tries to commit the page; returns undef on _success_ and
	# a version of the page with the rcs's conflict markers on failure.
	# The file is relative to the srcdir.
	my $file=shift;
	my $message=shift;
	my $rcstoken=shift;
	my $user=shift;
	my $ipaddr=shift;

	if (defined $user) {
		$message="web commit by $user".(length $message ? ": $message" : "");
	}
	elsif (defined $ipaddr) {
		$message="web commit from $ipaddr".(length $message ? ": $message" : "");
	}

	if (-d "$config{srcdir}/.svn") {
		# Check to see if the page has been changed by someone
		# else since rcs_prepedit was called.
		my ($oldrev)=$rcstoken=~/^([0-9]+)$/; # untaint
		my $rev=svn_info("Revision", "$config{srcdir}/$file");
		if (defined $rev && defined $oldrev && $rev != $oldrev) {
			# Merge their changes into the file that we've
			# changed.
			if (system("svn", "merge", "--quiet", "-r$oldrev:$rev",
			           "$config{srcdir}/$file", "$config{srcdir}/$file") != 0) {
				warn("svn merge -r$oldrev:$rev failed\n");
			}
		}

		if (system("svn", "commit", "--quiet", 
		           "--encoding", "UTF-8", "-m",
		           possibly_foolish_untaint($message),
			   $config{srcdir}) != 0) {
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

	eval q{
		use Date::Parse;
		use XML::SAX;
		use XML::Simple;
	};
	error($@) if $@;

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

		my $when=str2time($logentry->{date}, 'UTC');

		foreach my $msgline (split(/\n/, $logentry->{msg})) {
			push @message, { line => $msgline };
		}

		my $committype="web";
		if (defined $message[0] &&
		    $message[0]->{line}=~/$config{web_commit_regexp}/) {
			$user=defined $2 ? "$2" : "$3";
			$message[0]->{line}=$4;
		}
		else {
			$committype="svn";
		}

		foreach my $file (keys %{$logentry->{paths}}) {
			if (length $config{svnpath}) {
				next unless $file=~/^\/\Q$config{svnpath}\E\/([^ ]+)(?:$|\s)/;
				$file=$1;
			}

			my $diffurl=$config{diffurl};
			$diffurl=~s/\[\[file\]\]/$file/g;
			$diffurl=~s/\[\[r1\]\]/$rev - 1/eg;
			$diffurl=~s/\[\[r2\]\]/$rev/g;

			push @pages, {
				page => pagename($file),
				diffurl => $diffurl,
			} if length $file;
		}
		push @ret, {
			rev => $rev,
			user => $user,
			committype => $committype,
			when => $when,
			message => [@message],
			pages => [@pages],
		} if @pages;
		return @ret if @ret >= $num;
	}

	return @ret;
} #}}}

sub rcs_diff ($) { #{{{
	my $rev=possibly_foolish_untaint(int(shift));
	return `svnlook diff $config{svnrepo} -r$rev --no-diff-deleted`;
} #}}}

sub rcs_getctime ($) { #{{{
	my $file=shift;

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
		
	eval q{use Date::Parse};
	error($@) if $@;
	$date=str2time($date);
	debug("found ctime ".localtime($date)." for $file");
	return $date;
} #}}}

1
