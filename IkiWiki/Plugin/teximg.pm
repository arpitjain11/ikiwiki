#!/usr/bin/perl
# Licensed under GPL v2 or greater
# (c) 2007 Patrick Winnertz <patrick.winnertz@skolelinux.org>

package IkiWiki::Plugin::teximg;
use warnings;
use strict;
use Digest::MD5 qw(md5_hex);
use File::Temp qw(tempdir);
use HTML::Entities;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "preprocess", id => "teximg", call => \&preprocess);
} #}}}

sub preprocess (@) { #{{{
	my %params = @_;
	
	my $height = $params{height};
	if (! defined $height || ! length $height) {
		$height = 12;
	}
	else {
		$height =~ s#(\d+)#$1#;
	}
	
	my $code = $params{code};
	if (! defined $code && ! length $code) {
		return "[[teximg ".gettext("missing tex code"). "]]";
	}

	if (check($code)) {
		return create($code, check_height($height), \%params);
	}
	else {
		return "[[teximg ".gettext("code includes disallowed latex commands"). "]]";
	}
} #}}}

sub check_height ($) { #{{{
	# Since latex doesn't support unlimited scaling this function
	# returns the closest supported size.
	my $height =shift;

	my @allowed=(8,9,10,11,12,14,17,20);

	my $ret;
	my $fit;
	foreach my $val (@allowed) {
		my $f = abs($val - $height);
		if (! defined($fit) || $f < $fit ) {
			$ret=$val;
			$fit=$f;
		}
	}
	return $ret;
} #}}}

sub create ($$$) { #{{{
	# This function calls the image generating function and returns
	# the <img .. /> for the generated image.
	my $code = shift;
	my $height = shift;
	my $params = shift;

	if (! defined($height) and not length($height) ) {
		$height = 12;
	}

	my $digest = md5_hex($code, $height);

	my $imglink= $params->{page} . "/$digest.png";
	my $imglog =  $params->{page} .  "/$digest.log";
	will_render($params->{page}, $imglink);
	will_render($params->{page}, $imglog);

	my $imgurl=urlto($imglink, $params->{destpage});
	my $logurl=urlto($imglog, $params->{destpage});
	
	if (-e "$config{destdir}/$imglink" ||
	    gen_image($code, $height, $digest, $params->{page})) {
		return qq{<img src="$imgurl" alt="}
			.(exists $params->{alt} ? $params->{alt} : encode_entities($code))
			.qq{" class="teximg" />};
	}
	else {
		return qq{[[teximg <a href="$logurl">}.gettext("failed to generate image from code")."</a>]]";
	}
} #}}}

sub gen_image ($$$$) { #{{{
	# Actually creates the image.
	my $code = shift;
	my $height = shift;
	my $digest = shift;
	my $imagedir = shift;

	#TODO This should move into the setup file.
	my $tex = '\documentclass['.$height.'pt]{scrartcl}';
	$tex .= '\usepackage[version=3]{mhchem}';
	$tex .= '\usepackage{amsmath}';
	$tex .= '\usepackage{amsfonts}';
	$tex .= '\usepackage{amssymb}';
	$tex .= '\pagestyle{empty}';
	$tex .= '\begin{document}';
	$tex .= '$$'.$code.'$$';
	$tex .= '\end{document}';

	my $tmp = eval { create_tmp_dir($digest) };
	if (! $@ &&
	    writefile("$digest.tex", $tmp, $tex) &&
	    system("cd $tmp; latex --interaction=nonstopmode $tmp/$digest.tex > /dev/null") == 0 &&
	    system("dvips -E $tmp/$digest.dvi -o $tmp/$digest.ps 2> $tmp/$digest.log") == 0 &&
	    # ensure destination directory exists
	    writefile("$imagedir/$digest.png", $config{destdir}, "") &&
	    system("convert -density 120  -trim -transparent \"#FFFFFF\" $tmp/$digest.ps $config{destdir}/$imagedir/$digest.png > $tmp/$digest.log") == 0) {
		return 1;
	}
	else {
		# store failure log
		my $log;
		{
			open(my $f, '<', "$tmp/$digest.log");
			local $/=undef;
			$log = <$f>;
			close($f);
		}
		writefile("$digest.log", "$config{destdir}/$imagedir", $log);

		return 0;
	}
} #}}}

sub create_tmp_dir ($) { #{{{
	# Create a temp directory, it will be removed when ikiwiki exits.
	my $base = shift;

	my $template = $base.".XXXXXXXXXX";
	my $tmpdir = tempdir($template, TMPDIR => 1, CLEANUP => 1);
	return $tmpdir;
} #}}}

sub check ($) { #{{{
	# Check if the code is ok
	my $code = shift;

	my @badthings = (
		qr/\$\$/,
		qr/\\include/,
		qr/\\includegraphic/,
		qr/\\usepackage/,
		qr/\\newcommand/, 
		qr/\\renewcommand/,
		qr/\\def/,
		qr/\\input/,
		qr/\\open/,
		qr/\\loop/,
		qr/\\errorstopmode/,
		qr/\\scrollmode/,
		qr/\\batchmode/,
		qr/\\read/,
		qr/\\write/,
	);
	
	foreach my $thing (@badthings) {
		if ($code =~ m/$thing/ ) {
			return 0;
		}
	}
	return 1;
} #}}}

1
