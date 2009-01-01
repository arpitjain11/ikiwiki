#!/usr/bin/perl
package IkiWiki::Plugin::poll;

use warnings;
use strict;
use IkiWiki 3.00;
use Encode;

sub import {
	hook(type => "getsetup", id => "poll", call => \&getsetup);
	hook(type => "preprocess", id => "poll", call => \&preprocess);
	hook(type => "sessioncgi", id => "poll", call => \&sessioncgi);
}

sub getsetup () {
	return 
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

my %pagenum;
sub preprocess (@) {
	my %params=(open => "yes", total => "yes", percent => "yes", @_);

	my $open=IkiWiki::yesno($params{open});
	my $showtotal=IkiWiki::yesno($params{total});
	my $showpercent=IkiWiki::yesno($params{percent});
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
		if ($open && exists $config{cgiurl}) {
			# use POST to avoid robots
			$ret.="<form method=\"POST\" action=\"$config{cgiurl}\">\n";
		}
		my $percent=$total > 0 ? int($choices{$choice} / $total * 100) : 0;
		$ret.="<p>\n";
		if ($showpercent) {
			$ret.="$choice ($percent%)\n";
		}
		else {
			$ret.="$choice ($choices{$choice})\n";
		}
		if ($open && exists $config{cgiurl}) {
			$ret.="<input type=\"hidden\" name=\"do\" value=\"poll\" />\n";
			$ret.="<input type=\"hidden\" name=\"num\" value=\"$pagenum{$params{page}}\" />\n";
			$ret.="<input type=\"hidden\" name=\"page\" value=\"$params{page}\" />\n";
			$ret.="<input type=\"hidden\" name=\"choice\" value=\"$choice\" />\n";
			$ret.="<input type=\"submit\" value=\"".gettext("vote")."\" />\n";
		}
		$ret.="</p>\n<hr class=poll align=left width=\"$percent%\"/>\n";
		if ($open && exists $config{cgiurl}) {
			$ret.="</form>\n";
		}
	}
	if ($showtotal) {
		$ret.="<span>".gettext("Total votes:")." $total</span>\n";
	}
	return "<div class=poll>$ret</div>";
}

sub sessioncgi ($$) {
	my $cgi=shift;
	my $session=shift;
	if (defined $cgi->param('do') && $cgi->param('do') eq "poll") {
		my $choice=decode_utf8($cgi->param('choice'));
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
		my $choice_param="poll_choice_${page}_$num";
		my $oldchoice=$session->param($choice_param);
		if (defined $oldchoice && $oldchoice eq $choice) {
			# Same vote; no-op.
			IkiWiki::redirect($cgi, urlto($page, undef, 1));
			exit;
		}

		my $prefix=$config{prefix_directives} ? "!poll" : "poll";

		my $content=readfile(srcfile($pagesources{$page}));
		# Now parse the content, find the right poll,
		# and find the choice within it, and increment its number.
		# If they voted before, decrement that one.
		my $edit=sub {
			my $escape=shift;
			my $params=shift;
			return "\\[[$prefix $params]]" if $escape;
			if (--$num == 0) {
				$params=~s/(^|\s+)(\d+)\s+"?\Q$choice\E"?(\s+|$)/$1.($2+1)." \"$choice\"".$3/se;
				if (defined $oldchoice) {
					$params=~s/(^|\s+)(\d+)\s+"?\Q$oldchoice\E"?(\s+|$)/$1.($2-1 >=0 ? $2-1 : 0)." \"$oldchoice\"".$3/se;
				}
			}
			return "[[$prefix $params]]";
		};
		$content =~ s{(\\?)\[\[\Q$prefix\E\s+([^]]+)\s*\]\]}{$edit->($1, $2)}seg;

		# Store their vote, update the page, and redirect to it.
		writefile($pagesources{$page}, $config{srcdir}, $content);
		$session->param($choice_param, $choice);
		IkiWiki::cgi_savesession($session);
		$oldchoice=$session->param($choice_param);
		if ($config{rcs}) {
			IkiWiki::disable_commit_hook();
			IkiWiki::rcs_commit($pagesources{$page}, "poll vote ($choice)",
				IkiWiki::rcs_prepedit($pagesources{$page}),
				$session->param("name"), $ENV{REMOTE_ADDR});
			IkiWiki::enable_commit_hook();
			IkiWiki::rcs_update();
		}
		require IkiWiki::Render;
		IkiWiki::refresh();
		IkiWiki::saveindex();

		# Need to set cookie in same http response that does the
		# redir.
		eval q{use CGI::Cookie};
		error($@) if $@;
		my $cookie = CGI::Cookie->new(-name=> $session->name, -value=> $session->id);
		print $cgi->redirect(-cookie => $cookie,
			-url => urlto($page, undef, 1));
		exit;
	}
}

1
