#!/usr/bin/perl
# -*- cperl-indent-level: 8; -*-
# Testcases for the Ikiwiki parentlinks plugin.

use warnings;
use strict;
use Test::More 'no_plan';

my %expected;

BEGIN { use_ok("IkiWiki"); }

# Init
%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";
$config{underlaydir}="underlays/basewiki";
$config{templatedir}="t/parentlinks/templates";
IkiWiki::loadplugins();
IkiWiki::checkconfig();

# Test data
$expected{'parentlinks'} =
  {
   "" => [],
   "ikiwiki" => [],
   "ikiwiki/pagespec" =>
     [ {depth => 0, height => 2, },
       {depth => 1, height => 1, },
     ],
   "ikiwiki/pagespec/attachment" =>
     [ {depth => 0, height => 3, depth_0 => 1, height_3 => 1},
       {depth => 1, height => 2, },
       {depth => 2, height => 1, },
     ],
  };

# Test function
sub test_loop($$) {
	my $loop=shift;
	my $expected=shift;
	my $template;
	my %params;

	ok($template=template('parentlinks.tmpl'), "template created");
	ok($params{template}=$template, "params populated");

	while ((my $page, my $exp) = each %{$expected}) {
		my @path=(split("/", $page));
		my $pagedepth=@path;
		my $msgprefix="$page $loop";

		# manually run the plugin hook
		$params{page}=$page;
		$template->clear_params();
		IkiWiki::Plugin::parentlinks::pagetemplate(%params);
		my $res=$template->param($loop);

		is(scalar(@$res), $pagedepth, "$msgprefix: path length");
		# logic & arithmetic validation tests
		for (my $i=0; $i<$pagedepth; $i++) {
			my $r=$res->[$i];
			is($r->{height}, $pagedepth - $r->{depth},
			   "$msgprefix\[$i\]: height = pagedepth - depth");
			ok($r->{depth} ge 0, "$msgprefix\[$i\]: depth>=0");
			ok($r->{height} ge 0, "$msgprefix\[$i\]: height>=0");
		}
		# comparison tests, iff the test-suite has been written
		if (scalar(@$exp) eq $pagedepth) {
			for (my $i=0; $i<$pagedepth; $i++) {
				my $e=$exp->[$i];
				my $r=$res->[$i];
				map { is($r->{$_}, $e->{$_}, "$msgprefix\[$i\]: $_"); } keys %$e;
			}
		}
		# else {
		# 	diag("Testsuite is incomplete for ($page,$loop); cannot run comparison tests.");
		# }
	}
}

# Main
test_loop('parentlinks', $expected{'parentlinks'});
