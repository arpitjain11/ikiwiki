#!/usr/bin/perl
package IkiWiki::Plugin::postsparkline;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	IkiWiki::loadplugin('sparkline');
	hook(type => "getsetup", id => "postsparkline", call => \&getsetup);
	hook(type => "preprocess", id => "postsparkline", call => \&preprocess);
}

sub getsetup () {
	return 
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess (@) {
	my %params=@_;

	if (! exists $params{max}) {
		$params{max}=100;
	}

	if (! exists $params{pages}) {
		return "";
	}

	if (! exists $params{time} || $params{time} ne 'mtime') {
		$params{timehash} = \%IkiWiki::pagectime;
	}
	else {
		$params{timehash} = \%IkiWiki::pagemtime;
	}

	if (! exists $params{formula}) {
		error gettext("missing formula")
	}
	my $formula=$params{formula};
	$formula=~s/[^a-zA-Z0-9]*//g;
	$formula=IkiWiki::possibly_foolish_untaint($formula);
	if (! length $formula ||
	    ! IkiWiki::Plugin::postsparkline::formula->can($formula)) {
		error gettext("unknown formula");
	}

	add_depends($params{page}, $params{pages});

	my @list;
	foreach my $page (keys %pagesources) {
		next if $page eq $params{page};
		if (pagespec_match($page, $params{pages}, location => $params{page})) {
			push @list, $page;
		}
	}
	
	@list = sort { $params{timehash}->{$b} <=> $params{timehash}->{$a} } @list;

	my @data=eval qq{IkiWiki::Plugin::postsparkline::formula::$formula(\\\%params, \@list)};
	if ($@) {
		error $@;
	}

	if (! @data) {
		# generate an empty graph
		push @data, 0 foreach 1..($params{max} / 2);
	}

	my $color=exists $params{color} ? "($params{color})" : "";

	delete $params{pages};
	delete $params{formula};
	delete $params{ftime};
	delete $params{color};
	return IkiWiki::Plugin::sparkline::preprocess(%params, 
		map { $_.$color => "" } reverse @data);
}

sub perfoo ($@) {
	my $sub=shift;
	my $params=shift;
	
	my $max=$params->{max};
	my ($first, $prev, $cur);
	my $count=0;
	my @data;
	foreach (@_) {
		$cur=$sub->($params->{timehash}->{$_});
		if (defined $prev) {
			if ($prev != $cur) {
				push @data, "$prev,$count";
				$count=0;
				last if --$max <= 0;

				for ($cur+1 .. $prev-1) {
					push @data, "$_,0";
					last if --$max == 0;
				}
			}
		}
		else {
			$first=$cur;
		}
		$count++;
		$prev=$cur;
	}

	return @data;
}

package IkiWiki::Plugin::postsparkline::formula;

sub peryear (@) {
	return IkiWiki::Plugin::postsparkline::perfoo(sub {
		return (localtime $_[0])[5];
	}, @_);
}

sub permonth (@) {
	return IkiWiki::Plugin::postsparkline::perfoo(sub {
		my ($month, $year)=(localtime $_[0])[4,5];
		return $year*12+$month;
	}, @_);
}

sub perday (@) {
	return IkiWiki::Plugin::postsparkline::perfoo(sub {
		my ($year, $yday)=(localtime $_[0])[5,7];
		return $year*365+$yday;
	}, @_);
}

sub interval ($@) {
	my $params=shift;

	my $max=$params->{max};
	my @data;
	for (my $i=1; $i < @_; $i++) {
		push @data, $params->{timehash}->{$_[$i-1]} - $params->{timehash}->{$_[$i]};
		last if --$max <= 0;
	}
	return @data;
}

1
