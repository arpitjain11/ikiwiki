#!/usr/bin/perl
# Table Of Contents generator
package IkiWiki::Plugin::toc;

use warnings;
use strict;
use IkiWiki 3.00;
use HTML::Parser;

sub import {
	hook(type => "getsetup", id => "toc", call => \&getsetup);
	hook(type => "preprocess", id => "toc", call => \&preprocess);
	hook(type => "format", id => "toc", call => \&format);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

my %tocpages;

sub preprocess (@) {
	my %params=@_;

	if ($params{page} eq $params{destpage}) {
		$params{levels}=1 unless exists $params{levels};

		# It's too early to generate the toc here, so just record the
		# info.
		$tocpages{$params{destpage}}=\%params;

		return "\n<div class=\"toc\"></div>\n";
	}
	else {
		# Don't generate toc in an inlined page, doesn't work
		# right.
		return "";
	}
}

sub format (@) {
	my %params=@_;
	my $content=$params{content};
	
	return $content unless exists $tocpages{$params{page}};
	%params=%{$tocpages{$params{page}}};

	my $p=HTML::Parser->new(api_version => 3);
	my $page="";
	my $index="";
	my %anchors;
	my $curlevel;
	my $startlevel=0;
	my $liststarted=0;
	my $indent=sub { "\t" x $curlevel };
	$p->handler(start => sub {
		my $tagname=shift;
		my $text=shift;
		if ($tagname =~ /^h(\d+)$/i) {
			my $level=$1;
			my $anchor="index".++$anchors{$level}."h$level";
			$page.="$text<a name=\"$anchor\"></a>";
	
			# Take the first header level seen as the topmost level,
			# even if there are higher levels seen later on.
			if (! $startlevel) {
				$startlevel=$level;
				$curlevel=$startlevel-1;
			}
			elsif ($level < $startlevel) {
				$level=$startlevel;
			}
			
			return if $level - $startlevel >= $params{levels};
	
			if ($level > $curlevel) {
				while ($level > $curlevel + 1) {
					$index.=&$indent."<ol>\n";
					$curlevel++;
					$index.=&$indent."<li class=\"L$curlevel\">\n";
				}
				$index.=&$indent."<ol>\n";
				$curlevel=$level;
				$liststarted=1;
			}
			elsif ($level < $curlevel) {
				while ($level < $curlevel) {
					$index.=&$indent."</li>\n" if $curlevel;
					$curlevel--;
					$index.=&$indent."</ol>\n";
				}
				$liststarted=0;
			}
				
			$index.=&$indent."</li>\n" unless $liststarted;
			$liststarted=0;
			$index.=&$indent."<li class=\"L$curlevel\">".
				"<a href=\"#$anchor\">";
	
			$p->handler(text => sub {
				$page.=join("", @_);
				$index.=join("", @_);
			}, "dtext");
			$p->handler(end => sub {
				my $tagname=shift;
				if ($tagname =~ /^h(\d+)$/i) {
					$p->handler(text => undef);
					$p->handler(end => undef);
					$index.="</a>\n";
				}
				$page.=join("", @_);
			}, "tagname, text");
		}
		else {
			$page.=$text;
		}
	}, "tagname, text");
	$p->handler(default => sub { $page.=join("", @_) }, "text");
	$p->parse($content);
	$p->eof;

	while ($startlevel && $curlevel >= $startlevel) {
		$index.=&$indent."</li>\n" if $curlevel;
		$curlevel--;
		$index.=&$indent."</ol>\n";
	}

	$page=~s/(<div class=\"toc\">)/$1\n$index/;
	return $page;
}

1
