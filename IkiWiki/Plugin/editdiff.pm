#!/usr/bin/perl
# This plugin adds a "Diff" button to the page edit form.
package IkiWiki::Plugin::editdiff;

use warnings;
use strict;
use IkiWiki 2.00;
use HTML::Entities;
use IPC::Open2;

sub import { #{{{
	hook(type => "formbuilder_setup", id => "editdiff",
		call => \&formbuilder_setup);
} #}}}

sub diff ($$) { #{{{
	my $orig=shift;
	my $content=shift;

	my $sigpipe=0;
	$SIG{PIPE} = sub { $sigpipe=1; };

	my $pid = open2(*DIFFOUT, *DIFFIN, 'diff', '-u', $orig, '-');
	binmode($_, ':utf8') foreach (*DIFFIN, *DIFFOUT);

	print DIFFIN $content;
	close DIFFIN;
	my $ret='';
	while (<DIFFOUT>) {
		if (defined $ret) {
			$ret.=$_;
		}
		elsif (/^\@\@/) {
			$ret=$_;
		}
	}
	close DIFFOUT;
	waitpid $pid, 0;

	$SIG{PIPE}="default";
	return "couldn't run diff\n" if $sigpipe;

	return "<pre>".encode_entities($ret)."</pre>";
} #}}}

sub formbuilder_setup { #{{{
	my %params=@_;
	my $form=$params{form};
	my $page=$form->field("page");

	return if $form->field("do") ne "edit";

	$page = IkiWiki::titlepage(IkiWiki::possibly_foolish_untaint($page));
	return unless exists $pagesources{$page};

	push @{$params{buttons}}, "Diff";

	if ($form->submitted eq "Diff") {
		my $content=$form->field('editcontent');
		$content=~s/\r\n/\n/g;
		$content=~s/\r/\n/g;

		my $diff = diff(srcfile($pagesources{$page}), $content);
		$form->tmpl_param("page_preview", $diff);
	}
} #}}}

1
