package IkiWiki::Plugin::table;
# by Victor Moral <victor@taquiones.net>

use warnings;
use strict;

use IkiWiki;
use IkiWiki::Plugin::mdwn;

my %defaults = (
	data	=> undef,
	file	=> undef,
	format	=> 'auto',
	sep_char	=>  {
		'csv'	=> ',',
		'dsv'	=> '\|',
	},
	class	=>  undef,
	header	=>  1,
);
                            
sub import { #{{{
	hook(type => "preprocess", id => "table", call => \&preprocess);
} # }}}

sub preprocess (@) { #{{{
	my %params = (%defaults, @_);

	if (defined $params{delimiter}) {
		$params{sep_char}->{$params{format}} = $params{delimiter};
	}
	if (defined $params{file}) {
		if (! $pagesources{$params{file}}) {
			return "[[table cannot find file]]";
		}
		$params{data} = readfile(srcfile($params{file}));
	}

	if (lc $params{format} eq 'auto') {
		# first try the more simple format
		if (is_dsv_data($params{data})) {
			$params{format} = 'dsv';
			$params{sep_char}->{dsv} = '\|';
		}
		else {
			$params{format} = 'csv';
			$params{sep_char}->{csv} = ',';
		}
	}

	my @data;
	if (lc $params{format} eq 'csv') {
		@data=read_csv(\%params);
	}
	elsif (lc $params{format} eq 'dsv') {
		@data=read_dsv(\%params);
	}
	else {
		return "[[table unknown data format]]";
	}
	
	my $header;
	if ($params{header} != 1) {
		$header=shift @data;
	}
	if (! @data) {
		return "[[table has empty data]]";
	}

	my $html = tidy_up(open_table(\%params, $header),
			build_rows(\%params, @data),
			close_table(\%params, $header));

	if (defined $params{file}) {
		return $html."\n\n".
			htmllink($params{page}, $params{destpage}, $params{file},
				linktext => gettext('Direct data download'));
	}
	else {  
		return $html;
	}            
} #}}}

sub tidy_up (@) { #{{{
	my $html="";

	foreach my $text (@_) {
		my $indentation = $text =~ m{thead>|tbody>}   ? 0 :
		                  $text =~ m{tr>}             ? 4 :
		                  $text =~ m{td>|th>}         ? 8 :
		                                                0;
		$html .= (' ' x $indentation)."$text\n";
	}

	return $html;
} #}}}

sub is_dsv_data ($) { #{{{
	my $text = shift;

	my ($line) = split(/\n/, $text);
	return $line =~ m{.+\|};
}

sub read_csv ($) { #{{{
	my $params=shift;
	my @text_lines = split(/\n/, $params->{data});

	eval q{use Text::CSV};
	error($@) if $@;
	my $csv = Text::CSV->new({ 
		sep_char	=> $params->{sep_char}->{csv},
		binary		=> 1,
	}) || error("could not create a Text::CSV object");
	
	my $l=0;
	my @data;
	foreach my $line (@text_lines) {
		$l++;
		if ($csv->parse($line)) {
			push(@data, [ $csv->fields() ]);
		}
		else {
			debug(sprintf(gettext('parse fail at line %d: %s'), 
				$l, $csv->error_input()));
		}
	}

	return @data;
} #}}}

sub read_dsv ($) { #{{{
	my $params = shift;
	my @text_lines = split(/\n/, $params->{data});

	my @data;
	my $splitter = qr{$params->{sep_char}->{dsv}};
	foreach my $line (@text_lines) {
		push @data, [ split($splitter, $line) ];
	}
    
	return @data;
} #}}}

sub open_table ($$) { #{{{
	my $params = shift;
	my $header = shift;

	my @items;
	push @items, defined $params->{class}
			? "<table class=\"".$params->{class}.'">'
			: '<table>';
        push @items, '<thead>','<tr>',
	             (map { "<th>".htmlize($params, $_)."</th>" } @$header),
                     '</tr>','</thead>' if defined $header;
	push @items, '<tbody>';
	
	return @items;
}

sub build_rows ($@) { #{{{
	my $params = shift;

	my @items;
	foreach my $record (@_) {
	        push @items, '<tr>',
		             (map { "<td>".htmlize($params, $_)."</td>" } @$record),
		             '</tr>';
	}
	return @items;
} #}}}
                 
sub close_table ($$) { #{{{
	my $params = shift;
	my $header = shift;

	my @items;
	push @items, '</tbody>' if defined $header;
	push @items, '</table>';
	return @items;
} #}}}

sub htmlize { #{{{
	my $params = shift;
	my $text = shift;

	$text=IkiWiki::preprocess($params->{page},
		$params->{destpage}, $text);
	$text=IkiWiki::htmlize($params->{page},
		pagetype($pagesources{$params->{page}}), $text);

	# hack to get rid of enclosing junk added by markdown
	$text=~s!^<p>!!;
	$text=~s!</p>$!!;
	chomp $text;

	return $text;
}

1
