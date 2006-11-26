#!/usr/bin/perl
package IkiWiki::Plugin::poll;

use warnings;
use strict;
use IkiWiki;
use URI;

sub import { #{{{
	hook(type => "preprocess", id => "poll", call => \&preprocess);
	hook(type => "cgi", id => "poll", call => \&cgi);
} # }}}

sub yesno ($) { #{{{
	my $val=shift;
	return (defined $val && lc($val) eq "yes");
} #}}}

my %pagenum;
sub preprocess (@) { #{{{
	my %params=(open => "yes", total => "yes", percent => "yes", @_);

	my $open=yesno($params{open});
	my $showtotal=yesno($params{total});
	my $percent=yesno($params{percent});
	$pagenum{$params{page}}++;

	my %choices;
	my @choices;
	my $total=0;
	while (@_) {
		my $key=shift;
		my $value=shift;

		next unless $key =~ /^\d+/;

		my $num=$key;
		$key=shift;
		$value=shift;

		$choices{$key}=$num;
		push @choices, $key;
		$total+=$num;
	}

	my $ret="";
	foreach my $choice (@choices) {
		my $percent=int($choices{$choice} / $total * 100);
		if ($percent) {
			$ret.="$choice ($percent%) ";
		}
		else {
			$ret.="$choice ($choices{$choice}) ";
		}
		if ($open && exists $config{cgiurl}) {
			my $url=URI->new($config{cgiurl});
			$url->query_form(
				"do" => "poll",
				"num" => $pagenum{$params{page}}, 
				"page" => $params{page}, 
				"choice" => $choice,
			);
			$ret.="<a class=pollbutton href=\"$url\">vote</a>";
		}
		$ret.="<br />\n<hr class=poll align=left width=\"$percent%\"/>\n";
	}
	if ($showtotal) {
		$ret.="<span>Total votes: $total</span>\n";
	}
	return "<div class=poll>$ret</div>";
} # }}}

sub cgi ($) { #{{{
	my $cgi=shift;
	if (defined $cgi->param('do') && $cgi->param('do') eq "poll") {
		my $choice=$cgi->param('choice');
		if (! defined $choice) {
			error("no choice specified");
		}
		my $num=$cgi->param('num');
		if (! defined $num) {
			error("no num specified");
		}
		my $page=IkiWiki::possibly_foolish_untaint($cgi->param('page'));
		if (! defined $page || ! exists $pagesources{$page}) {
			error("bad page name");
		}

		# Did they vote before? If so, let them change their vote,
		# and check for dups.
		my $session=IkiWiki::cgi_getsession();
		my $choice_param="poll_choice_${page}_$num";
		my $oldchoice=$session->param($choice_param);
		if (defined $oldchoice && $oldchoice eq $choice) {
			# Same vote; no-op.
			IkiWiki::redirect($cgi, "$config{url}/".htmlpage($page));
		}

		my $content=readfile(srcfile($pagesources{$page}));
		# Now parse the content, find the right poll,
		# and find the choice within it, and increment its number.
		# If they voted before, decrement that one.
		my $edit=sub {
			my $escape=shift;
			my $params=shift;
			return "\\[[poll $params]]" if $escape;
			return $params unless --$num == 0;
			my @bits=split(' ', $params);
			my @ret;
			while (@bits) {
				my $n=shift @bits;
				if ($n=~/=/) {
					# val=param setting
					push @ret, $n;
					next;
				}
				my $c=shift @bits;
				$c=~s/^"(.*)"/$1/g;
				next unless defined $n && defined $c;
				if ($c eq $choice) {
					$n++;
				}
				if (defined $oldchoice && $c eq $oldchoice) {
					$n--;
				}
				push @ret, $n, "\"$c\"";
			}
			return "[[poll ".join(" ", @ret)."]]";
		};
		$content =~ s{(\\?)\[\[poll\s+([^]]+)\s*\]\]}{$edit->($1, $2)}seg;

		# Store their vote, update the page, and redirect to it.
		writefile($pagesources{$page}, $config{srcdir}, $content);
		$session->param($choice_param, $choice);
		IkiWiki::cgi_savesession($session);
		$oldchoice=$session->param($choice_param);
		if ($config{rcs}) {
			# prevent deadlock with post-commit hook
			IkiWiki::unlockwiki();
			IkiWiki::rcs_commit($pagesources{$page}, "poll vote",
				IkiWiki::rcs_prepedit($pagesources{$page}),
				$session->param("name"), $ENV{REMOTE_ADDR});
		}
		else {
			require IkiWiki::Render;
			IkiWiki::refresh();
			IkiWiki::saveindex();
		}
		# Need to set cookie in same http response that does the
		# redir.
		eval q{use CGI::Cookie};
		error($@) if $@;
		my $cookie = CGI::Cookie->new(-name=> $session->name, -value=> $session->id);
		print $cgi->redirect(-cookie => $cookie,
			-url => "$config{url}/".htmlpage($page));
		exit;
	}
} #}}}

1
