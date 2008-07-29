#!/usr/bin/perl
package IkiWiki::Plugin::autoindex;

use warnings;
use strict;
use IkiWiki 2.00;
use Encode;

sub import { #{{{
	hook(type => "refresh", id => "autoindex", call => \&refresh);
} # }}}

sub genindex ($) { #{{{
	my $page=shift;
	my $file=$page.".".$config{default_pageext};
	my $template=template("autoindex.tmpl");
	$template->param(page => $page);
	writefile($file, $config{srcdir}, $template->output);
} #}}}

sub refresh () { #{{{
	eval q{use File::Find};
	error($@) if $@;

	my (%pages, %dirs);
	find({
		no_chdir => 1,
		wanted => sub {
			$_=decode_utf8($_);
			if (IkiWiki::file_pruned($_, $config{srcdir})) {
				$File::Find::prune=1;
			}
			elsif (! -l $_) {
				my ($f)=/$config{wiki_file_regexp}/; # untaint
				return unless defined $f;
				$f=~s/^\Q$config{srcdir}\E\/?//;
				return unless length $f;
				if (! -d _) {
					$pages{pagename($f)}=1;
				}
				else {
					$dirs{$f}=1;
				}
			}
		}
	}, $config{srcdir});

	foreach my $dir (keys %dirs) {
		if (! exists $pages{$dir}) {
			genindex($dir);
		}
	}
} #}}}

1
