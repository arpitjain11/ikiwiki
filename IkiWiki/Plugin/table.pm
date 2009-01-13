package IkiWiki::Plugin::table;
# by Victor Moral <victor@taquiones.net>

use warnings;
use strict;
use Encode;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "table", call => \&getsetup);
	hook(type => "preprocess", id => "table", call => \&preprocess, scan => 1);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess (@) {
	my %params =(
		format	=> 'auto',
		header	=> 'row',
		@_
	);

	if (exists $params{file}) {
		if (! exists $pagesources{$params{file}}) {
			error gettext("cannot find file");
		}
		$params{data} = readfile(srcfile($params{file}));
		add_depends($params{page}, $params{file});
	}

	if (! defined wantarray) {
		# scan mode --	if the table uses an external file, need to
		# scan that file too.
		return unless exists $params{file};

		IkiWiki::run_hooks(scan => sub {
			shift->(
				page => $params{page},
				content => $params{data},
			);
		});

		# Preprocess in scan-only mode.
		IkiWiki::preprocess($params{page}, $params{page}, $params{data}, 1);

		return;
	}

	if (lc $params{format} eq 'auto') {
		# first try the more simple format
		if (is_dsv_data($params{data})) {
			$params{format} = 'dsv';
		}
		else {
			$params{format} = 'csv';
		}
	}

	my @data;
	if (lc $params{format} eq 'csv') {
		@data=split_csv($params{data},
			defined $params{delimiter} ? $params{delimiter} : ",",);
		# linkify after parsing since html link quoting can
		# confuse CSV parsing
		@data=map {
			[ map {
				IkiWiki::linkify($params{page},
					$params{destpage}, $_);
			} @$_ ]
		} @data;
	}
	elsif (lc $params{format} eq 'dsv') {
		# linkify before parsing since wikilinks can contain the
		# delimiter
		$params{data} = IkiWiki::linkify($params{page},
			$params{destpage}, $params{data});
		@data=split_dsv($params{data},
			defined $params{delimiter} ? $params{delimiter} : "|",);
	}
	else {
		error gettext("unknown data format");
	}

	my $header;
	if (lc($params{header}) eq "row" || IkiWiki::yesno($params{header})) {
		$header=shift @data;
	}
	if (! @data) {
		error gettext("empty data");
	}

	my @lines;
	push @lines, defined $params{class}
			? "<table class=\"".$params{class}.'">'
			: '<table>';
	push @lines, "\t<thead>",
		genrow(\%params, "th", @$header),
	        "\t</thead>" if defined $header;
	push @lines, "\t<tbody>" if defined $header;
	push @lines, genrow(\%params, "td", @$_) foreach @data;
	push @lines, "\t</tbody>" if defined $header;
	push @lines, '</table>';
	my $html = join("\n", @lines);

	if (exists $params{file}) {
		return $html."\n\n".
			htmllink($params{page}, $params{destpage}, $params{file},
				linktext => gettext('Direct data download'));
	}
	else {  
		return $html;
	}            
}

sub is_dsv_data ($) {
	my $text = shift;

	my ($line) = split(/\n/, $text);
	return $line =~ m{.+\|};
}

sub split_csv ($$) {
	my @text_lines = split(/\n/, shift);
	my $delimiter = shift;

	eval q{use Text::CSV};
	error($@) if $@;
	my $csv = Text::CSV->new({ 
		sep_char	=> $delimiter,
		binary		=> 1,
		allow_loose_quotes => 1,
	}) || error("could not create a Text::CSV object");
	
	my $l=0;
	my @data;
	foreach my $line (@text_lines) {
		$l++;
		if ($csv->parse($line)) {
			push(@data, [ map { decode_utf8 $_ } $csv->fields() ]);
		}
		else {
			debug(sprintf(gettext('parse fail at line %d: %s'), 
				$l, $csv->error_input()));
		}
	}

	return @data;
}

sub split_dsv ($$) {
	my @text_lines = split(/\n/, shift);
	my $delimiter = shift;
	$delimiter="|" unless defined $delimiter;

	my @data;
	foreach my $line (@text_lines) {
		push @data, [ split(/\Q$delimiter\E/, $line, -1) ];
	}
    
	return @data;
}

sub genrow ($@) {
	my %params=%{shift()};
	my $elt = shift;
	my @data = @_;

	my $page=$params{page};
	my $destpage=$params{destpage};
	my $type=pagetype($pagesources{$page});

	my @ret;
	push @ret, "\t\t<tr>";
	for (my $x=0; $x < @data; $x++) {
		my $cell=IkiWiki::htmlize($page, $destpage, $type,
		         IkiWiki::preprocess($page, $destpage, $data[$x]));

		# automatic colspan for empty cells
		my $colspan=1;
		while ($x+1 < @data && $data[$x+1] eq '') {
			$x++;
			$colspan++;
		}

		# check if the first column should be a header
		my $e=$elt;
		if ($x == 0 && lc($params{header}) eq "column") {
			$e="th";
		}

		if ($colspan > 1) {
			push @ret, "\t\t\t<$e colspan=\"$colspan\">$cell</$e>"
		}
		else {
			push @ret, "\t\t\t<$e>$cell</$e>"
		}
	}
	push @ret, "\t\t</tr>";

	return @ret;
}

1
