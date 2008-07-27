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

sub dumpline ($$$$) { #{{{
	my $key=shift;
	my $value=shift;
	my $type=shift;
	my $prefix=shift;
	
	eval q{use Data::Dumper};
	error($@) if $@;
	local $Data::Dumper::Terse=1;
	local $Data::Dumper::Indent=1;
	local $Data::Dumper::Pad="\t";
	local $Data::Dumper::Sortkeys=1;
	local $Data::Dumper::Quotekeys=0;
	
	my $dumpedvalue;
	if ($type eq 'boolean' || $type eq 'integer') {
		# avoid quotes
		$dumpedvalue=$value;
	}
	elsif ($type eq 'string' && ref $value eq 'ARRAY' && @$value &&
	    ! grep { /[^-A-Za-z0-9_]/ } @$value) {
		# dump simple array as qw{}
		$dumpedvalue="[qw{ ".join(" ", @$value)." }]";
	}
	else {
		$dumpedvalue=Dumper($value);
		chomp $dumpedvalue;
		if (length $prefix) {
			# add to second and subsequent lines
			my @lines=split(/\n/, $dumpedvalue);
			$dumpedvalue="";
			for (my $x=0; $x <= $#lines; $x++) {
				$lines[$x] =~ s/^\t//;
				$dumpedvalue.="\t".($x ? $prefix : "").$lines[$x]."\n";
			}
		}
		$dumpedvalue=~s/^\t//;
		chomp $dumpedvalue;
	}
	
	return "\t$prefix$key => $dumpedvalue,";
} #}}}

sub dumpvalues ($@) { #{{{
	my $setup=shift;
	my @ret;
	while (@_) {
		my $key=shift;
		my %info=%{shift()};

		next if $info{type} eq "internal";
		
		push @ret, "\t# ".$info{description} if exists $info{description};
		
		if (exists $setup->{$key} && defined $setup->{$key}) {
			push @ret, dumpline($key, $setup->{$key}, $info{type}, "");
			delete $setup->{$key};
		}
		elsif (exists $info{example}) {
			push @ret, dumpline($key, $info{example}, $info{type}, "#");
		}
	}
	return @ret;
} #}}}

sub gendump ($) { #{{{
	my $description=shift;
	my %setup=(%config);
	my @ret;
	
	push @ret, "\t# basic setup";
	push @ret, dumpvalues(\%setup, IkiWiki::getsetup());

	# Load all plugins, so that all setup options are available.
	my @plugins=grep { ! /externaldemo|pythondemo/ } sort(IkiWiki::listplugins());
	foreach my $plugin (@plugins) {
		eval { IkiWiki::loadplugin($plugin) };
		if (exists $IkiWiki::hooks{checkconfig}{$plugin}{call}) {
			my @s=eval { $IkiWiki::hooks{checkconfig}{$plugin}{call}->() };
		}
	}
	unshift @plugins, $config{rcs} if $config{rcs};

	foreach my $id (@plugins) {
		my $title="\t# $id".($id ne $config{rcs} ? " plugin" : "");
		if (exists $IkiWiki::hooks{getsetup}{$id}{call}) {
			# use an array rather than a hash, to preserve order
			my @s=eval { $IkiWiki::hooks{getsetup}{$id}{call}->() };
			next unless @s;
			push @ret, "", $title;
			push @ret, dumpvalues(\%setup, @s);
		}
	}
	
	unshift @ret,
		"#!/usr/bin/perl",
		"# $description",
		"#",
		"# Passing this to ikiwiki --setup will make ikiwiki generate",
		"# wrappers and build the wiki.",
		"#",
		"# Remember to re-run ikiwiki --setup any time you edit this file.",
		"use IkiWiki::Setup::Standard {";
	push @ret, "}";

	return @ret;
} #}}}

1
