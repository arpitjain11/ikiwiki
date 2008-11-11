#!/usr/bin/perl
# Ikiwiki tag plugin.
package IkiWiki::Plugin::tag;

use warnings;
use strict;
use IkiWiki 2.00;

my %tags;

sub import { #{{{
	hook(type => "getopt", id => "tag", call => \&getopt);
	hook(type => "getsetup", id => "tag", call => \&getsetup);
	hook(type => "preprocess", id => "tag", call => \&preprocess_tag, scan => 1);
	hook(type => "preprocess", id => "taglink", call => \&preprocess_taglink, scan => 1);
	hook(type => "pagetemplate", id => "tag", call => \&pagetemplate);
} # }}}

sub getopt () { #{{{
	eval q{use Getopt::Long};
	error($@) if $@;
	Getopt::Long::Configure('pass_through');
	GetOptions("tagbase=s" => \$config{tagbase});
} #}}}

sub getsetup () { #{{{
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
		tagbase => {
			type => "string",
			example => "tag",
			description => "parent page tags are located under",
			safe => 1,
			rebuild => 1,
		},
} #}}}

sub tagpage ($) { #{{{
	my $tag=shift;
			
	if ($tag !~ m{^\.?/} &&
	    defined $config{tagbase}) {
		$tag="/".$config{tagbase}."/".$tag;
		$tag=~y#/#/#s; # squash dups
	}

	return $tag;
} #}}}

sub taglink ($$$;@) { #{{{
	my $page=shift;
	my $destpage=shift;
	my $tag=shift;
	my %opts=@_;

	return htmllink($page, $destpage, tagpage($tag), %opts);
} #}}}

sub preprocess_tag (@) { #{{{
	if (! @_) {
		return "";
	}
	my %params=@_;
	my $page = $params{page};
	delete $params{page};
	delete $params{destpage};
	delete $params{preview};

	foreach my $tag (keys %params) {
		$tag=linkpage($tag);
		$tags{$page}{$tag}=1;
		# hidden WikiLink
		push @{$links{$page}}, tagpage($tag);
	}
		
	return "";
} # }}}

sub preprocess_taglink (@) { #{{{
	if (! @_) {
		return "";
	}
	my %params=@_;
	return join(" ", map {
		if (/(.*)\|(.*)/) {
			my $tag=linkpage($2);
			$tags{$params{page}}{$tag}=1;
			push @{$links{$params{page}}}, tagpage($tag);
			return taglink($params{page}, $params{destpage}, $tag,
				linktext => pagetitle($1));
		}
		else {
			my $tag=linkpage($_);
			$tags{$params{page}}{$tag}=1;
			push @{$links{$params{page}}}, tagpage($tag);
			return taglink($params{page}, $params{destpage}, $tag);
		}
	}
	grep {
		$_ ne 'page' && $_ ne 'destpage' && $_ ne 'preview'
	} keys %params);
} # }}}

sub pagetemplate (@) { #{{{
	my %params=@_;
	my $page=$params{page};
	my $destpage=$params{destpage};
	my $template=$params{template};

	$template->param(tags => [
		map { 
			link => taglink($page, $destpage, $_, rel => "tag")
		}, sort keys %{$tags{$page}}
	]) if exists $tags{$page} && %{$tags{$page}} && $template->query(name => "tags");

	if ($template->query(name => "categories")) {
		# It's an rss/atom template. Add any categories.
		if (exists $tags{$page} && %{$tags{$page}}) {
			$template->param(categories => [map { category => $_ },
				sort keys %{$tags{$page}}]);
		}
	}
} # }}}

1
