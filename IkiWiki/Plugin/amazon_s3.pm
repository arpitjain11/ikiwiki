#!/usr/bin/perl
package IkiWiki::Plugin::amazon_s3;

use warnings;
no warnings 'redefine';
use strict;
use IkiWiki 2.00;
use IkiWiki::Render;
use Net::Amazon::S3;

# Store references to real subs before overriding them.
our %subs;
BEGIN {
	foreach my $sub (qw{IkiWiki::writefile IkiWiki::prune}) {
		$subs{$sub}=\&$sub;
	}
};

sub import { #{{{
	hook(type => "checkconfig", id => "amazon_s3", call => \&checkconfig);
} # }}}

sub checkconfig { #{{{
	foreach my $field (qw{amazon_s3_key_id amazon_s3_key_file
	                      amazon_s3_bucket}) {
		if (! exists $config{$field} || ! defined $config{$field}) {
			error(sprintf(gettext("Must specify %s"), $field));
		}
	}
	if (! exists $config{amazon_s3_prefix} ||
	    ! defined $config{amazon_s3_prefix}) {
	    $config{amazon_s3_prefix}="wiki/";
	}
} #}}}

{
my $bucket;
sub getbucket { #{{{
	return $bucket if defined $bucket;
	
	open(IN, "<", $config{amazon_s3_key_file}) || error($config{amazon_s3_key_file}.": ".$!);
	my $key=<IN>;
	chomp $key;
	close IN;

	my $s3=Net::Amazon::S3->new({
		aws_access_key_id => $config{amazon_s3_key_id},
		aws_secret_access_key => $key,
		retry => 1,
	});

	# make sure the bucket exists
	if (exists $config{amazon_s3_location}) {
		$bucket=$s3->add_bucket({
			bucket => $config{amazon_s3_bucket},
			location_constraint => $config{amazon_s3_location},
		});
	}
	else {
		$bucket=$s3->add_bucket({
			bucket => $config{amazon_s3_bucket},
		});
	}

	if (! $bucket) {
		error(gettext("Failed to create bucket in S3: ").
			$s3->err.": ".$s3->errstr."\n");
	}

	return $bucket;
} #}}}
}

package IkiWiki;
use File::MimeInfo;
use Encode;

# This is a wrapper around the real writefile.
sub writefile ($$$;$$) { #{{{
        my $file=shift;
        my $destdir=shift;
        my $content=shift;
        my $binary=shift;
        my $writer=shift;

	# First, write the file to disk.
	my $ret=$IkiWiki::Plugin::amazon_s3::subs{'IkiWiki::writefile'}->($file, $destdir, $content, $binary, $writer);

	# Now, determine if the file was written to the destdir.
	# writefile might be used for writing files elsewhere.
	# Also, $destdir might be set to a subdirectory of the destdir.
	my $key;
	if ($destdir eq $config{destdir}) {
		$key=$file;
	}
	elsif ("$destdir/$file" =~ /^\Q$config{destdir}\/\E(.*)/) {
		$key=$1;
	}

	# Store the data in S3.
	if (defined $key) {
		$key=$config{amazon_s3_prefix}.$key;
		my $bucket=IkiWiki::Plugin::amazon_s3::getbucket();

		# The http layer tries to downgrade utf-8
		# content, but that can fail (see
		# http://rt.cpan.org/Ticket/Display.html?id=35710),
		# so force convert it to bytes.
		$content=encode_utf8($content) if defined $content;

		if (defined $content && ! length $content) {
			# S3 doesn't allow storing empty files!
			$content=" ";
		}
		
		my %opts=(
			acl_short => 'public-read',
			content_type => mimetype("$destdir/$file"),
		);
		my $res;
		if (! $writer) {
			$res=$bucket->add_key($key, $content, \%opts);
		}
		else {
			# read back in the file that the writer emitted
			$res=$bucket->add_key_filename($key, "$destdir/$file", \%opts);
		}
		if ($res && $key=~/(^|.*\/)index.$config{htmlext}$/) {
			# index.html files are a special case. Since S3 is
			# not a normal web server, it won't serve up
			# foo/index.html when foo/ is requested. So the
			# file has to be stored twice. (This is bad news
			# when usedirs is enabled!)
			# TODO: invesitgate using the new copy operation.
			#       (It may not be robust enough.)
			my $base=$1;
			if (! $writer) {
				$res=$bucket->add_key($base, $content, \%opts);
			}
			else {
				$res=$bucket->add_key_filename($base, "$destdir/$file", \%opts);
			}
		}
		if (! $res) {
			error(gettext("Failed to save file to S3: ").
				$bucket->err.": ".$bucket->errstr."\n");
		}
	}

	return $ret;
} #}}}

# This is a wrapper around the real prune.
sub prune ($) { #{{{
	my $file=shift;

	# If a file in the destdir is being pruned, need to delete it out
	# of S3 as well.
	if ($file =~ /^\Q$config{destdir}\/\E(.*)/) {
		my $key=$config{amazon_s3_prefix}.$1;
		my $bucket=IkiWiki::Plugin::amazon_s3::getbucket();
		my $res=$bucket->delete_key($key);
		if ($res && $key=~/(^|.*\/)index.$config{htmlext}$/) {
			# index.html special case: Delete other file too
			$res=$bucket->delete_key($1);
		}
		if (! $res) {
			error(gettext("Failed to delete file from S3: ").
				$bucket->err.": ".$bucket->errstr."\n");
		}
	}

	return $IkiWiki::Plugin::amazon_s3::subs{'IkiWiki::prune'}->($file);
} #}}}

1
