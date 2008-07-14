#!/usr/bin/perl
# -*- cperl-indent-level: 8; -*-
# Testcases for the Ikiwiki pedigree plugin.

use warnings;
use strict;
use Test::More 'no_plan';

my %expected;

BEGIN { use_ok("IkiWiki"); }

# Init
%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";
$config{underlaydir}="underlays/basewiki";
$config{templatedir}="t/pedigree/templates";
IkiWiki::loadplugins();
IkiWiki::checkconfig();
ok(IkiWiki::loadplugin("pedigree"), "pedigree plugin loaded");

# Test data
$expected{'pedigree'} =
  {
   "" => [],
   "ikiwiki" => [],
   "ikiwiki/pagespec" => [
			  {absdepth => 0,
			   distance => 2,
			   is_root => 1,
			   is_second_ancestor => '',
			   is_grand_mother => 1,
			   is_mother => '',
			  },
			  {absdepth => 1,
			   distance => 1,
			   is_root => '',
			   is_second_ancestor => 1,
			   is_grand_mother => '',
			   is_mother => 1,
			  },
			 ],
   "ikiwiki/pagespec/attachment" => [
				     {absdepth => 0,
				      distance => 3,
				      is_root => 1,
				      is_second_ancestor => '',
				      is_grand_mother => '',
				      is_mother => '',
				     },
				     {absdepth => 1,
				      distance => 2,
				      is_root => '',
				      is_second_ancestor => 1,
				      is_grand_mother => 1,
				      is_mother => '',
				     },
				     {absdepth => 2,
				      distance => 1,
				      is_root => '',
				      is_second_ancestor => '',
				      is_grand_mother => '',
				      is_mother => 1,
				     },
				    ],
  };

$expected{'pedigree_but_root'} =
  {
   "" => [],
   "ikiwiki" => [],
   "ikiwiki/pagespec" => [],
   "ikiwiki/pagespec/attachment" => [],
  };

$expected{'pedigree_but_two_oldest'} =
  {
   "" => [],
   "ikiwiki" => [],
   "ikiwiki/pagespec" => [],
   "ikiwiki/pagespec/attachment" => [],
  };

# Test function
sub test_loop($$) {
	my $loop=shift;
	my $expected=shift;
	my $template;
	my %params;
	my $offset;

	if ($loop eq 'pedigree') {
		$offset=0;
	} elsif ($loop eq 'pedigree_but_root') {
		$offset=1;
	} elsif ($loop eq 'pedigree_but_two_oldest') {
		$offset=2;
	}

	ok($template=template('pedigree.tmpl'), "template created");
	ok($params{template}=$template, "params populated");

	while ((my $page, my $exp) = each %{$expected}) {
		my @path=(split("/", $page));
		my $pagedepth=@path;
		my $expdepth;
		if (($pagedepth - $offset) >= 0) {
			$expdepth=$pagedepth - $offset;
		} else {
			$expdepth=0;
		}
		my $msgprefix="$page $loop";

		# manually run the plugin hook
		$params{page}=$page;
		$template->clear_params();
		IkiWiki::Plugin::pedigree::pagetemplate(%params);
		my $res=$template->param($loop);

		is(scalar(@$res), $expdepth, "$msgprefix: path length");
		# logic & arithmetic validation tests
		for (my $i=0; $i<$expdepth; $i++) {
			my $r=$res->[$i];
			is($r->{distance}, $pagedepth - $r->{absdepth},
			   "$msgprefix\[$i\]: distance = pagedepth - absdepth");
			ok($r->{absdepth} ge 0, "$msgprefix\[$i\]: absdepth>=0");
			ok($r->{distance} ge 0, "$msgprefix\[$i\]: distance>=0");
			unless ($loop eq 'pedigree') {
				ok($r->{reldepth} ge 0, "$msgprefix\[$i\]: reldepth>=0");
			      TODO: {
					local $TODO = "Known bug" if 
					  (($loop eq 'pedigree_but_root')
					   && ($i >= $offset));
					is($r->{reldepth} + $offset, $r->{absdepth},
					   "$msgprefix\[$i\]: reldepth+offset=absdepth");
				}
			}
		}
		# comparison tests, iff the test-suite has been written
		if (scalar(@$exp) eq $expdepth) {
			for (my $i=0; $i<$expdepth; $i++) {
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
map {
	test_loop($_, $expected{$_});
} ('pedigree', 'pedigree_but_root', 'pedigree_but_two_oldest');
