#!/usr/bin/perl
# graphviz plugin for ikiwiki: render graphviz source as an image.
# Josh Triplett
package IkiWiki::Plugin::graphviz;

use warnings;
use strict;
use IkiWiki 3.00;
use IPC::Open2;

sub import {
	hook(type => "getsetup", id => "graphviz", call => \&getsetup);
	hook(type => "preprocess", id => "graph", call => \&graph);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

my %graphviz_programs = (
	"dot" => 1, "neato" => 1, "fdp" => 1, "twopi" => 1, "circo" => 1
);

sub render_graph (\%) {
	my %params = %{(shift)};

	my $src = "$params{type} g {\n";
	$src .= "charset=\"utf-8\";\n";
	$src .= "ratio=compress;\nsize=\"".($params{width}+0).", ".($params{height}+0)."\";\n"
		if defined $params{width} and defined $params{height};
	$src .= $params{src};
	$src .= "}\n";

	# Use the sha1 of the graphviz code as part of its filename.
	eval q{use Digest::SHA1};
	error($@) if $@;
	my $dest=$params{page}."/graph-".
		IkiWiki::possibly_foolish_untaint(Digest::SHA1::sha1_hex($src)).
		".png";
	will_render($params{page}, $dest);

	if (! -e "$config{destdir}/$dest") {
		my $pid;
		my $sigpipe=0;
		$SIG{PIPE}=sub { $sigpipe=1 };
		$pid=open2(*IN, *OUT, "$params{prog} -Tpng");

		# open2 doesn't respect "use open ':utf8'"
		binmode (OUT, ':utf8');

		print OUT $src;
		close OUT;

		my $png;
		{
			local $/ = undef;
			$png = <IN>;
		}
		close IN;

		waitpid $pid, 0;
		$SIG{PIPE}="DEFAULT";
		error gettext("failed to run graphviz") if $sigpipe;

		if (! $params{preview}) {
			writefile($dest, $config{destdir}, $png, 1);
		}
		else {
			# can't write the file, so embed it in a data uri
			eval q{use MIME::Base64};
			error($@) if $@;
			return "<img src=\"data:image/png;base64,".
				encode_base64($png)."\" />";
		}
	}

	if ($params{preview}) {
		return "<img src=\"".urlto($dest, "")."\" />\n";
	}
	else {
		return "<img src=\"".urlto($dest, $params{destpage})."\" />\n";
	}
}

sub graph (@) {
	my %params=@_;
	$params{src} = "" unless defined $params{src};
	$params{type} = "digraph" unless defined $params{type};
	$params{prog} = "dot" unless defined $params{prog};
	error gettext("prog not a valid graphviz program") unless $graphviz_programs{$params{prog}};

	return render_graph(%params);
}

1
