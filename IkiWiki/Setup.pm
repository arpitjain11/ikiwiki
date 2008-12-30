#!/usr/bin/perl
# Ikiwiki setup files are perl files that 'use IkiWiki::Setup::foo',
# passing it some sort of configuration data.

package IkiWiki::Setup;

use warnings;
use strict;
use IkiWiki;
use open qw{:utf8 :std};
use File::Spec;

sub load ($) {
	my $setup=IkiWiki::possibly_foolish_untaint(shift);
	$config{setupfile}=File::Spec->rel2abs($setup);

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
}

sub merge ($) {
	# Merge setup into existing config and untaint.
	my %setup=%{shift()};

	if (exists $setup{add_plugins} && exists $config{add_plugins}) {
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
				if ($c eq 'wrappers') {
					# backwards compatability code
					$config{$c}=$setup{$c};
				}
				else {
					$config{$c}=[map { IkiWiki::possibly_foolish_untaint($_) } @{$setup{$c}}]
				}
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
	
	if (length $config{cgi_wrapper}) {
		push @{$config{wrappers}}, {
			cgi => 1,
			wrapper => $config{cgi_wrapper},
			wrappermode => (defined $config{cgi_wrappermode} ? $config{cgi_wrappermode} : "06755"),
		};
	}
}

sub getsetup () {
	# Gets all available setup data from all plugins. Returns an
	# ordered list of [plugin, setup] pairs.
	my @ret;

        # disable logging to syslog while dumping, broken plugins may
	# whine when loaded
	my $syslog=$config{syslog};
        $config{syslog}=undef;

	# Load all plugins, so that all setup options are available.
	my @plugins=grep { $_ ne $config{rcs} } sort(IkiWiki::listplugins());
	unshift @plugins, $config{rcs} if $config{rcs}; # rcs plugin 1st
	foreach my $plugin (@plugins) {
		eval { IkiWiki::loadplugin($plugin) };
		if (exists $IkiWiki::hooks{checkconfig}{$plugin}{call}) {
			my @s=eval { $IkiWiki::hooks{checkconfig}{$plugin}{call}->() };
		}
	}

	foreach my $plugin (@plugins) {
		if (exists $IkiWiki::hooks{getsetup}{$plugin}{call}) {
			# use an array rather than a hash, to preserve order
			my @s=eval { $IkiWiki::hooks{getsetup}{$plugin}{call}->() };
			next unless @s;
			push @ret, [ $plugin, \@s ],
		}
	}
	
        $config{syslog}=$syslog;

	return @ret;
}

sub dump ($) {
	my $file=IkiWiki::possibly_foolish_untaint(shift);
	
	require IkiWiki::Setup::Standard;
	my @dump=IkiWiki::Setup::Standard::gendump("Setup file for ikiwiki.");

	open (OUT, ">", $file) || die "$file: $!";
	print OUT "$_\n" foreach @dump;
	close OUT;
}

1
