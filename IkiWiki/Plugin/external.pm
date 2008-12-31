#!/usr/bin/perl
# Support for external plugins written in other languages.
# Communication via XML RPC to a pipe.
# See externaldemo for an example of a plugin that uses this.
package IkiWiki::Plugin::external;

use warnings;
use strict;
use IkiWiki 3.00;
use RPC::XML;
use RPC::XML::Parser;
use IPC::Open2;
use IO::Handle;

my %plugins;

sub import {
	my $self=shift;
	my $plugin=shift;
	return unless defined $plugin;

	my ($plugin_read, $plugin_write);
	my $pid = open2($plugin_read, $plugin_write,
		IkiWiki::possibly_foolish_untaint($plugin));

	# open2 doesn't respect "use open ':utf8'"
	binmode($plugin_read, ':utf8');
	binmode($plugin_write, ':utf8');

	$plugins{$plugin}={in => $plugin_read, out => $plugin_write, pid => $pid,
		accum => ""};
	$RPC::XML::ENCODING="utf-8";

	rpc_call($plugins{$plugin}, "import");
}

sub rpc_write ($$) {
	my $fh=shift;
	my $string=shift;

	$fh->print($string."\n");
	$fh->flush;
}

sub rpc_call ($$;@) {
	my $plugin=shift;
	my $command=shift;

	# send the command
	my $req=RPC::XML::request->new($command, @_);
	rpc_write($plugin->{out}, $req->as_string);

	# process incoming rpc until a result is available
	while ($_ = $plugin->{in}->getline) {
		$plugin->{accum}.=$_;
		while ($plugin->{accum} =~ /^\s*(<\?xml\s.*?<\/(?:methodCall|methodResponse)>)\n(.*)/s) {
			$plugin->{accum}=$2;
			my $r = RPC::XML::Parser->new->parse($1);
			error("XML RPC parser failure: $r") unless ref $r;
			if ($r->isa('RPC::XML::response')) {
				my $value=$r->value;
				if ($r->is_fault($value)) {
					# throw the error as best we can
					print STDERR $value->string."\n";
					return "";
				}
				elsif ($value->isa('RPC::XML::array')) {
					return @{$value->value};
				}
				elsif ($value->isa('RPC::XML::struct')) {
					my %hash=%{$value->value};

					# XML-RPC v1 does not allow for
					# nil/null/None/undef values to be
					# transmitted, so until
					# XML::RPC::Parser honours v2
					# (<nil/>), external plugins send
					# a hash with one key "null" pointing
					# to an empty string.
					if (exists $hash{null} &&
					    $hash{null} eq "" &&
					    int(keys(%hash)) == 1) {
						return undef;
					}

					return %hash;
				}
				else {
					return $value->value;
				}
			}

			my $name=$r->name;
			my @args=map { $_->value } @{$r->args};

			# When dispatching a function, first look in 
			# IkiWiki::RPC::XML. This allows overriding
			# IkiWiki functions with RPC friendly versions.
			my $ret;
			if (exists $IkiWiki::RPC::XML::{$name}) {
				$ret=$IkiWiki::RPC::XML::{$name}($plugin, @args);
			}
			elsif (exists $IkiWiki::{$name}) {
				$ret=$IkiWiki::{$name}(@args);
			}
			else {
				error("XML RPC call error, unknown function: $name");
			}

			# XML-RPC v1 does not allow for nil/null/None/undef
			# values to be transmitted, so until XML::RPC::Parser
			# honours v2 (<nil/>), send a hash with one key "null"
			# pointing to an empty string.
			if (! defined $ret) {
				$ret={"null" => ""};
			}

			my $string=eval { RPC::XML::response->new($ret)->as_string };
			if ($@ && ref $ret) {
				# One common reason for serialisation to
				# fail is a complex return type that cannot
				# be represented as an XML RPC response.
				# Handle this case by just returning 1.
				$string=eval { RPC::XML::response->new(1)->as_string };
			}
			if ($@) {
				error("XML response serialisation failed: $@");
			}
			rpc_write($plugin->{out}, $string);
		}
	}

	return undef;
}

package IkiWiki::RPC::XML;
use Memoize;

sub getvar ($$$) {
	my $plugin=shift;
	my $varname="IkiWiki::".shift;
	my $key=shift;

	no strict 'refs';
	my $ret=$varname->{$key};
	use strict 'refs';
	return $ret;
}

sub setvar ($$$;@) {
	my $plugin=shift;
	my $varname="IkiWiki::".shift;
	my $key=shift;
	my $value=shift;

	no strict 'refs';
	my $ret=$varname->{$key}=$value;
	use strict 'refs';
	return $ret;
}

sub getstate ($$$$) {
	my $plugin=shift;
	my $page=shift;
	my $id=shift;
	my $key=shift;

	return $IkiWiki::pagestate{$page}{$id}{$key};
}

sub setstate ($$$$;@) {
	my $plugin=shift;
	my $page=shift;
	my $id=shift;
	my $key=shift;
	my $value=shift;

	return $IkiWiki::pagestate{$page}{$id}{$key}=$value;
}

sub getargv ($) {
	my $plugin=shift;

	return \@ARGV;
}

sub setargv ($@) {
	my $plugin=shift;
	my $array=shift;

	@ARGV=@$array;
}

sub inject ($@) {
	# Bind a given perl function name to a particular RPC request.
	my $plugin=shift;
	my %params=@_;

	if (! exists $params{name} || ! exists $params{call}) {
		die "inject needs name and call parameters";
	}
	my $sub = sub {
		IkiWiki::Plugin::external::rpc_call($plugin, $params{call}, @_)
	};
	$sub=memoize($sub) if $params{memoize};

	# This will add it to the symbol table even if not present.
	no warnings;
	eval qq{*$params{name}=\$sub};
	use warnings;

	# This will ensure that everywhere it was exported to sees
	# the injected version.
	IkiWiki::inject(name => $params{name}, call => $sub);
	return 1;
}

sub hook ($@) {
	# the call parameter is a function name to call, since XML RPC
	# cannot pass a function reference
	my $plugin=shift;
	my %params=@_;

	my $callback=$params{call};
	delete $params{call};

	IkiWiki::hook(%params, call => sub {
		IkiWiki::Plugin::external::rpc_call($plugin, $callback, @_);
	});
}

sub pagespec_match ($@) {
	# convert pagespec_match's return object into a XML RPC boolean
	my $plugin=shift;

	return RPC::XML::boolean->new(0 + IkiWiki::pagespec_march(@_));
}

1
