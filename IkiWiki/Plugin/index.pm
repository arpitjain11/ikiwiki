#!/usr/bin/perl
package IkiWiki::Plugin::index;

use warnings;
use strict;
use IkiWiki 2.00;
use File::Spec;

sub import { #{{{
	hook(type => "preprocess", id => "index", call => \&preprocess, scan => 1);
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;

	if ($params{page} eq $params{destpage}) {
		my $indexpage=IkiWiki::dirname($params{page});
		my $dest=targetpage($indexpage, "html");
		
		# Dummy up all wiki state needed to create the index page,
		# with the same source as the page containing the
		# index directive.
		$pagesources{$indexpage}=$pagesources{$params{page}};
		$destsources{targetpage($indexpage, "html")}=$params{page};
		$IkiWiki::pagecase{lc $indexpage}=$indexpage;
		$links{$indexpage}=[] unless exists $links{$indexpage};
		$IkiWiki::pagemtime{$indexpage}=$IkiWiki::pagemtime{$params{page}};
		$IkiWiki::pagectime{$indexpage}=$IkiWiki::pagectime{$params{page}};
		
		# It's too late to let regular page rendering, so create an
		# index.html symlink pointing at the page containing the
		# index directive.
		# XXX this means that backlinks won't be right
		will_render($indexpage, $dest);
		# TODO: create minimum relative symlink
		symlink(File::Spec->rel2abs($config{destdir}."/".targetpage($params{page}, "html")),
			File::Spec->rel2abs($config{destdir}."/".$dest));
	}
} # }}}

1
