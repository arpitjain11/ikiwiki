#!/usr/bin/perl
# Standard ikiwiki setup module.
# Parameters to import should be all the standard ikiwiki config stuff,
# plus an array of wrappers to set up.

package IkiWiki::Setup::Standard;

use warnings;
use strict;
use IkiWiki;

sub import { #{{{
	$IkiWiki::Setup::raw_setup=$_[1];
} #}}}

sub dumpline ($$$) { #{{{
	my $key=shift;
	my $value=shift;
	my $prefix=shift;
	
	eval q{use Data::Dumper};
	error($@) if $@;
	local $Data::Dumper::Terse=1;
	local $Data::Dumper::Indent=1;
	local $Data::Dumper::Pad="\t";
	local $Data::Dumper::Sortkeys=1;
	local $Data::Dumper::Quotekeys=0;
	
	my $dumpedvalue=Dumper($value);
	chomp $dumpedvalue;
	$dumpedvalue=~s/^\t//;
	
	return "\t$prefix$key=$dumpedvalue,";
} #}}}

sub dumpvalues ($@) { #{{{
	my $setup=shift;
	my @ret;
	while (@_) {
		my $key=shift;
		my %info=%{shift()};
		
		push @ret, "\t# ".$info{description} if exists $info{description};
		
		if (exists $setup->{$key} && defined $setup->{$key}) {
			push @ret, dumpline($key, $setup->{$key}, "");
			delete $setup->{$key};
		}
		elsif (exists $info{default}) {
			push @ret, dumpline($key, $info{default}, "#");
		}
		elsif (exists $info{example}) {
			push @ret, dumpline($key, $info{example}, "#");
		}
	}
	return @ret;
} #}}}

sub dump ($) { #{{{
	my $file=shift;
	
	my %setup=(%config);
	my @ret;

	foreach my $id (sort keys %{$IkiWiki::hooks{getsetup}}) {
		# use an array rather than a hash, to preserve order
		my @s=$IkiWiki::hooks{getsetup}{$id}{call}->();
		return unless @s;
		push @ret, "\t# $id plugin";
		push @ret, dumpvalues(\%setup, @s);
		push @ret, "";
	}
	
	if (%setup) {
		push @ret, "\t# other";
		foreach my $key (sort keys %setup) {
			push @ret, dumpline($key, $setup{$key}, "");
		}
	}
	
	unshift @ret, "#!/usr/bin/perl
# Setup file for ikiwiki.
# Passing this to ikiwiki --setup will make ikiwiki generate wrappers and
# build the wiki.
#
# Remember to re-run ikiwiki --setup any time you edit this file.

use IkiWiki::Setup::Standard {";
	push @ret, "}";

	open (OUT, ">", $file) || die "$file: $!";
	print OUT "$_\n" foreach @ret;
	close OUT;
} #}}}

1
