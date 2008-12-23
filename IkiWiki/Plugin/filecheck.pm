#!/usr/bin/perl
package IkiWiki::Plugin::filecheck;

use warnings;
use strict;
use IkiWiki 3.00;

my %units=( #{{{	# size in bytes
	B		=> 1,
	byte		=> 1,
	KB		=> 2 ** 10,
	kilobyte 	=> 2 ** 10,
	K		=> 2 ** 10,
	KB		=> 2 ** 10,
	kilobyte 	=> 2 ** 10,
	M		=> 2 ** 20,
	MB		=> 2 ** 20,
	megabyte	=> 2 ** 20,
	G		=> 2 ** 30,
	GB		=> 2 ** 30,
	gigabyte	=> 2 ** 30,
	T		=> 2 ** 40,
	TB		=> 2 ** 40,
	terabyte	=> 2 ** 40,
	P		=> 2 ** 50,
	PB		=> 2 ** 50,
	petabyte	=> 2 ** 50,
	E		=> 2 ** 60,
	EB		=> 2 ** 60,
	exabyte		=> 2 ** 60,
	Z		=> 2 ** 70,
	ZB		=> 2 ** 70,
	zettabyte	=> 2 ** 70,
	Y		=> 2 ** 80,
	YB		=> 2 ** 80,
	yottabyte	=> 2 ** 80,
	# ikiwiki, if you find you need larger data quantities, either modify
	# yourself to add them, or travel back in time to 2008 and kill me.
	#   -- Joey
);

sub parsesize ($) {
	my $size=shift;

	no warnings;
	my $base=$size+0; # force to number
	use warnings;
	foreach my $unit (sort keys %units) {
		if ($size=~/[0-9\s]\Q$unit\E$/i) {
			return $base * $units{$unit};
		}
	}
	return $base;
}

# This is provided for other plugins that want to convert back the other way.
sub humansize ($) {
	my $size=shift;

	foreach my $unit (reverse sort { $units{$a} <=> $units{$b} || $b cmp $a } keys %units) {
		if ($size / $units{$unit} > 0.25) {
			return (int($size / $units{$unit} * 10)/10).$unit;
		}
	}
	return $size; # near zero, or negative
}

package IkiWiki::PageSpec;

sub match_maxsize ($$;@) {
	my $page=shift;
	my $maxsize=eval{IkiWiki::Plugin::filecheck::parsesize(shift)};
	if ($@) {
		return IkiWiki::FailReason->new("unable to parse maxsize (or number too large)");
	}

	my %params=@_;
	my $file=exists $params{file} ? $params{file} : $IkiWiki::pagesources{$page};
	if (! defined $file) {
		return IkiWiki::FailReason->new("no file specified");
	}

	if (-s $file > $maxsize) {
		return IkiWiki::FailReason->new("file too large (".(-s $file)." >  $maxsize)");
	}
	else {
		return IkiWiki::SuccessReason->new("file not too large");
	}
}

sub match_minsize ($$;@) {
	my $page=shift;
	my $minsize=eval{IkiWiki::Plugin::filecheck::parsesize(shift)};
	if ($@) {
		return IkiWiki::FailReason->new("unable to parse minsize (or number too large)");
	}

	my %params=@_;
	my $file=exists $params{file} ? $params{file} : $IkiWiki::pagesources{$page};
	if (! defined $file) {
		return IkiWiki::FailReason->new("no file specified");
	}

	if (-s $file < $minsize) {
		return IkiWiki::FailReason->new("file too small");
	}
	else {
		return IkiWiki::SuccessReason->new("file not too small");
	}
}

sub match_mimetype ($$;@) {
	my $page=shift;
	my $wanted=shift;

	my %params=@_;
	my $file=exists $params{file} ? $params{file} : $IkiWiki::pagesources{$page};
	if (! defined $file) {
		return IkiWiki::FailReason->new("no file specified");
	}

	# Use ::magic to get the mime type, the idea is to only trust
	# data obtained by examining the actual file contents.
	eval q{use File::MimeInfo::Magic};
	if ($@) {
		return IkiWiki::FailReason->new("failed to load File::MimeInfo::Magic ($@); cannot check MIME type");
	}
	my $mimetype=File::MimeInfo::Magic::magic($file);
	if (! defined $mimetype) {
		$mimetype=File::MimeInfo::Magic::default($file);
		if (! defined $mimetype) {
			$mimetype="unknown";
		}
	}

	my $regexp=IkiWiki::glob2re($wanted);
	if ($mimetype!~/^$regexp$/i) {
		return IkiWiki::FailReason->new("file MIME type is $mimetype, not $wanted");
	}
	else {
		return IkiWiki::SuccessReason->new("file MIME type is $mimetype");
	}
}

sub match_virusfree ($$;@) {
	my $page=shift;
	my $wanted=shift;

	my %params=@_;
	my $file=exists $params{file} ? $params{file} : $IkiWiki::pagesources{$page};
	if (! defined $file) {
		return IkiWiki::FailReason->new("no file specified");
	}

	if (! exists $IkiWiki::config{virus_checker} ||
	    ! length $IkiWiki::config{virus_checker}) {
		return IkiWiki::FailReason->new("no virus_checker configured");
	}

	# The file needs to be fed into the virus checker on stdin,
	# because the file is not world-readable, and if clamdscan is
	# used, clamd would fail to read it.
	eval q{use IPC::Open2};
	error($@) if $@;
	open (IN, "<", $file) || return IkiWiki::FailReason->new("failed to read file");
	binmode(IN);
	my $sigpipe=0;
	$SIG{PIPE} = sub { $sigpipe=1 };
	my $pid=open2(\*CHECKER_OUT, "<&IN", $IkiWiki::config{virus_checker}); 
	my $reason=<CHECKER_OUT>;
	chomp $reason;
	1 while (<CHECKER_OUT>);
	close(CHECKER_OUT);
	waitpid $pid, 0;
	$SIG{PIPE}="DEFAULT";
	if ($sigpipe || $?) {
		if (! length $reason) {
			$reason="virus checker $IkiWiki::config{virus_checker}; failed with no output";
		}
		return IkiWiki::FailReason->new("file seems to contain a virus ($reason)");
	}
	else {
		return IkiWiki::SuccessReason->new("file seems virusfree ($reason)");
	}
}

sub match_ispage ($$;@) {
	my $filename=shift;

	if (defined IkiWiki::pagetype($filename)) {
		return IkiWiki::SuccessReason->new("file is a wiki page");
	}
	else {
		return IkiWiki::FailReason->new("file is not a wiki page");
	}
}
