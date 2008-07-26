#!/usr/bin/perl
# Ikiwiki setup files are perl files that 'use IkiWiki::Setup::foo',
# passing it some sort of configuration data.

package IkiWiki::Setup;

use warnings;
use strict;
use IkiWiki;
use open qw{:utf8 :std};

# There can be multiple modules, with different configuration styles.
# The setup modules each convert the data into the hashes used by ikiwiki
# internally (if it's not already in that format), and store it in
# IkiWiki::Setup::$raw_setup, to pass it back to this module.
our $raw_setup;

sub load ($) { # {{{
	my $setup=IkiWiki::possibly_foolish_untaint(shift);
	delete $config{setup};
	#translators: The first parameter is a filename, and the second
	#translators: is a (probably not translated) error message.
	open (IN, $setup) || error(sprintf(gettext("cannot read %s: %s"), $setup, $!));
	my $code;
	{
		local $/=undef;
		$code=<IN>;
	}
	($code)=$code=~/(.*)/s;
	close IN;

	eval $code;
	error("$setup: ".$@) if $@;

	my %setup=%{$raw_setup};
	$raw_setup=undef;

	# Merge setup into existing config and untaint.
	if (exists $setup{add_plugins}) {
		push @{$setup{add_plugins}}, @{$config{add_plugins}};
	}
	if (exists $setup{exclude}) {
		push @{$config{wiki_file_prune_regexps}}, $setup{exclude};
	}
	foreach my $c (keys %setup) {
		if (defined $setup{$c}) {
			if (! ref $setup{$c} || ref $setup{$c} eq 'Regexp') {
				$config{$c}=IkiWiki::possibly_foolish_untaint($setup{$c});
			}
			elsif (ref $setup{$c} eq 'ARRAY') {
				$config{$c}=[map { IkiWiki::possibly_foolish_untaint($_) } @{$setup{$c}}]
			}
			elsif (ref $setup{$c} eq 'HASH') {
				foreach my $key (keys %{$setup{$c}}) {
					$config{$c}{$key}=IkiWiki::possibly_foolish_untaint($setup{$c}{$key});
				}
			}
		}
		else {
			$config{$c}=undef;
		}
	}
} #}}}

sub dump ($) { #{{{
	my $file=IkiWiki::possibly_foolish_untaint(shift);
	
	require IkiWiki::Setup::Standard;
	my @dump=IkiWiki::Setup::Standard::gendump("Setup file for ikiwiki.");

	open (OUT, ">", $file) || die "$file: $!";
	print OUT "$_\n" foreach @dump;
	close OUT;
}

1
