#!/usr/bin/perl
package IkiWiki::Plugin::autoindex;

use warnings;
use strict;
use IkiWiki 2.00;
use Encode;

sub import { #{{{
	hook(type => "getsetup", id => "autoindex", call => \&getsetup);
	hook(type => "refresh", id => "autoindex", call => \&refresh);
} # }}}

sub getsetup () { #{{{
	return
		plugin => {
			safe => 1,
			rebuild => 0,
		},
} #}}}

sub genindex ($) { #{{{
	my $page=shift;
	my $file=$page.".".$config{default_pageext};
	my $template=template("autoindex.tmpl");
	$template->param(page => $page);
	writefile($file, $config{srcdir}, $template->output);
	if ($config{rcs}) {
		IkiWiki::rcs_add($file);
	}
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

	my @needed;
	foreach my $dir (keys %dirs) {
		if (! exists $pages{$dir}) {
			push @needed, $dir;
		}
	}
	
	if (@needed) {
		if ($config{rcs}) {
			IkiWiki::disable_commit_hook();
		}
		genindex($_) foreach @needed;
		if ($config{rcs}) {
			IkiWiki::rcs_commit_staged(
				gettext("automatic index generation"),
				undef, undef);
			IkiWiki::enable_commit_hook();
		}
	}
} #}}}

1
