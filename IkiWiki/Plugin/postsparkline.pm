#!/usr/bin/perl
package IkiWiki::Plugin::postsparkline;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	IkiWiki::loadplugin('sparkline');
	hook(type => "preprocess", id => "postsparkline", call => \&preprocess);
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;

	if (! exists $params{max}) {
		$params{max}=100;
	}

	if (! exists $params{pages}) {
		return "";
	}

	if (! exists $params{formula}) {
		return "[[postsparkline ".gettext("missing formula")."]]";
	}
	my $formula=$params{formula};
	$formula=~s/[^a-zA-Z0-9]*//g;
	$formula=IkiWiki::possibly_foolish_untaint($formula);
	if (! length $formula ||
	    ! IkiWiki::Plugin::postsparkline::formula->can($formula)) {
		return "[[postsparkline ".gettext("unknown formula")."]]";
	}

	add_depends($params{page}, $params{pages});

	my @list;
	foreach my $page (keys %pagesources) {
		next if $page eq $params{page};
		if (pagespec_match($page, $params{pages}, location => $params{page})) {
			push @list, $page;
		}
	}
	
	@list = sort { $IkiWiki::pagectime{$b} <=> $IkiWiki::pagectime{$a} } @list;

	delete $params{pages};
	delete $params{formula};
	my @data=eval qq{IkiWiki::Plugin::postsparkline::formula::$formula(\\\%params, \@list)};
	if ($@) {
		return "[[postsparkline error $@]]";
	}
	return IkiWiki::Plugin::sparkline::preprocess(%params, 
		map { $_ => "" } reverse @data);
} # }}}

sub perfoo ($@) {
	my $sub=shift;
	my $params=shift;
	
	my $max=$params->{max};
	my ($first, $prev, $cur);
	my $count=0;
	my @data;
	foreach (@_) {
		$cur=$sub->($IkiWiki::pagectime{$_});
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
		push @data, $IkiWiki::pagectime{$_[$i-1]} - $IkiWiki::pagectime{$_[$i]};
		last if --$max <= 0;
	}
	return @data;
}

1
