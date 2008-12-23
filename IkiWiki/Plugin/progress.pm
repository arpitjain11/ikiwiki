#!/usr/bin/perl
package IkiWiki::Plugin::progress;

use warnings;
use strict;
use IkiWiki 3.00;

my $percentage_pattern = qr/[0-9]+\%?/; # pattern to validate percentages

sub import {
	hook(type => "getsetup", id => "progress", call => \&getsetup);
	hook(type => "preprocess", id => "progress", call => \&preprocess);
	hook(type => "format",     id => "progress", call => \&format);
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
	
	my $fill;
	
	if (defined $params{percent}) {
		$fill = $params{percent};
		($fill) = $fill =~ m/($percentage_pattern)/; # fill is untainted now
		$fill=~s/%$//;
		if (! defined $fill || ! length $fill || $fill > 100 || $fill < 0) {
			error(sprintf(gettext("illegal percent value %s"), $params{percent}));
		}
		$fill.="%";
	}
	elsif (defined $params{totalpages} and defined $params{donepages}) {
		add_depends($params{page}, $params{totalpages});
		add_depends($params{page}, $params{donepages});

		my @pages=keys %pagesources;
		my $totalcount=0;
		my $donecount=0;
		foreach my $page (@pages) {
			$totalcount++ if pagespec_match($page, $params{totalpages}, location => $params{page});
			$donecount++ if pagespec_match($page, $params{donepages}, location => $params{page});
		}
		
		if ($totalcount == 0) {
			$fill = "100%";
		}
		else {
			my $number = $donecount/$totalcount*100;
			$fill = sprintf("%u%%", $number);
		}
	}
	else {
		error(gettext("need either `percent` or `totalpages` and `donepages` parameters"));
	}

	return <<EODIV
<div class="progress">
  <div class="progress-done" style="width: $fill">$fill</div>
</div>
EODIV
}

sub format(@) {
	my %params = @_;

	# If HTMLScrubber has removed the style attribute, then bring it back

	$params{content} =~ s!<div class="progress-done">($percentage_pattern)</div>!<div class="progress-done" style="width: $1">$1</div>!g;

	return $params{content};    
}

1
