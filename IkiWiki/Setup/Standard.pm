#!/usr/bin/perl
# Standard ikiwiki setup module.
# Parameters to import should be all the standard ikiwiki config stuff,
# plus an array of wrappers to set up.

package IkiWiki::Setup::Standard;

use warnings;
use strict;

sub import { #{{{
	$IkiWiki::Setup::raw_setup=$_[1];
} #}}}

sub generate (@) { #{{{
	my %setup=@_;

	eval q{use Data::Dumper};
	error($@) if $@;
	local $Data::Dumper::Terse=1;
	local $Data::Dumper::Indent=1;
	local $Data::Dumper::Pad="\t";
	local $Data::Dumper::Sortkeys=1;
	local $Data::Dumper::Quotekeys=0;

	my @ret="#!/usr/bin/perl
# Setup file for ikiwiki.
# Passing this to ikiwiki --setup will make ikiwiki generate wrappers and
# build the wiki.
#
# Remember to re-run ikiwiki --setup any time you edit this file.

use IkiWiki::Setup::Standard {";

	foreach my $id (sort keys %{$IkiWiki::hooks{getsetup}}) {
		my @setup=$IkiWiki::hooks{getsetup}{$id}{call}->();
		return unless @setup;
		push @ret, "\t# $id plugin";
		while (@setup) {
			my $key=shift @setup;
			my %info=%{shift @setup};
	
			push @ret, "\t# ".$info{description} if exists $info{description};
	
			my $value=undef;
			my $prefix="#";
			if (exists $setup{$key} && defined $setup{$key}) {
				$value=$setup{$key};
				$prefix="";
			}
			elsif (exists $info{default}) {
				$value=$info{default};
			}
			elsif (exists $info{example}) {
				$value=$info{example};
			}
	
			my $dumpedvalue=Dumper($value);
			chomp $dumpedvalue;
			$dumpedvalue=~/^\t//;
			push @ret, "\t$prefix$key=$dumpedvalue,";
		}
		push @ret, "";
	}

	push @ret, "}";
	return @ret;
} #}}}

1
