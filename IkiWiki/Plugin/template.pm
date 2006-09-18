#!/usr/bin/perl
# Structured template plugin.
package IkiWiki::Plugin::template;

use warnings;
use strict;
use IkiWiki;
use HTML::Template;
use Encode;

sub import { #{{{
	hook(type => "preprocess", id => "template", call => \&preprocess);
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;

	if (! exists $params{id}) {
		return "[[template missing id parameter]]"
	}

	my $template_page="templates/$params{id}";
	add_depends($params{page}, $template_page);

	my $template_file=$pagesources{$template_page};
	return "[[template ".
	       htmllink($params{page}, $params{destpage}, $template_page).
	       " not found]]"
		unless defined $template_file;

	my $template=HTML::Template->new(
        	filter => sub {
                        my $text_ref = shift;
                        $$text_ref=&Encode::decode_utf8($$text_ref);
			chomp $$text_ref;
                },
                filename => srcfile($template_file),
                die_on_bad_params => 0,
		no_includes => 1,
		blind_cache => 1,
	);

	foreach my $param (keys %params) {
		$template->param($param => $params{$param});
	}

	return IkiWiki::preprocess($params{page}, $params{destpage},
		$template->output);
} # }}}

1
