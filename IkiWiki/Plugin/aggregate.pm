#!/usr/bin/perl
# Blog aggregation plugin.
package IkiWiki::Plugin::aggregate;

use warnings;
use strict;
use IkiWiki 2.00;
use HTML::Entities;
use HTML::Parser;
use HTML::Tagset;
use URI;
use open qw{:utf8 :std};

my %feeds;
my %guids;

sub import { #{{{
	hook(type => "getopt", id => "aggregate", call => \&getopt);
	hook(type => "checkconfig", id => "aggregate", call => \&checkconfig);
	hook(type => "needsbuild", id => "aggregate", call => \&needsbuild);
	hook(type => "preprocess", id => "aggregate", call => \&preprocess);
        hook(type => "delete", id => "aggregate", call => \&delete);
	hook(type => "savestate", id => "aggregate", call => \&savestate);
} # }}}

sub getopt () { #{{{
        eval q{use Getopt::Long};
	error($@) if $@;
        Getopt::Long::Configure('pass_through');
        GetOptions("aggregate" => \$config{aggregate});
} #}}}

sub checkconfig () { #{{{
	if ($config{aggregate} && ! ($config{post_commit} && 
	                             IkiWiki::commit_hook_enabled())) {
		if (! IkiWiki::lockwiki(0)) {
			debug("wiki is locked by another process, not aggregating");
			exit 1;
		}
		
		# Fork a child process to handle the aggregation.
		# The parent process will then handle building the result.
		# This avoids messy code to clear state accumulated while
		# aggregating.
		defined(my $pid = fork) or error("Can’t fork: $!");
		if (! $pid) {
			loadstate();
			IkiWiki::loadindex();
			aggregate();
			expire();
			savestate();
			exit 0;
		}
		waitpid($pid,0);
		if ($?) {
			error "aggregation failed with code $?";
		}
		
		IkiWiki::unlockwiki();
	}
} #}}}

sub needsbuild (@) { #{{{
	my $needsbuild=shift;
	
	loadstate(); # if not already loaded

	foreach my $feed (values %feeds) {
		if (grep { $_ eq $pagesources{$feed->{sourcepage}} } @$needsbuild) {
			# Mark all feeds originating on this page as removable;
			# preprocess will unmark those that still exist.
			remove_feeds($feed->{sourcepage});
		}
	}
} # }}}

sub preprocess (@) { #{{{
	my %params=@_;

	foreach my $required (qw{name url}) {
		if (! exists $params{$required}) {
			return "[[aggregate ".sprintf(gettext("missing %s parameter"), $required)."]]";
		}
	}

	my $feed={};
	my $name=$params{name};
	if (exists $feeds{$name}) {
		$feed=$feeds{$name};
	}
	else {
		$feeds{$name}=$feed;
	}
	$feed->{name}=$name;
	$feed->{sourcepage}=$params{page};
	$feed->{url}=$params{url};
	my $dir=exists $params{dir} ? $params{dir} : $params{page}."/".IkiWiki::titlepage($params{name});
	$dir=~s/^\/+//;
	($dir)=$dir=~/$config{wiki_file_regexp}/;
	$feed->{dir}=$dir;
	$feed->{feedurl}=defined $params{feedurl} ? $params{feedurl} : "";
	$feed->{updateinterval}=defined $params{updateinterval} ? $params{updateinterval} * 60 : 15 * 60;
	$feed->{expireage}=defined $params{expireage} ? $params{expireage} : 0;
	$feed->{expirecount}=defined $params{expirecount} ? $params{expirecount} : 0;
	delete $feed->{remove};
	delete $feed->{expired};
	$feed->{lastupdate}=0 unless defined $feed->{lastupdate};
	$feed->{numposts}=0 unless defined $feed->{numposts};
	$feed->{newposts}=0 unless defined $feed->{newposts};
	$feed->{message}=gettext("new feed") unless defined $feed->{message};
	$feed->{error}=0 unless defined $feed->{error};
	$feed->{tags}=[];
	while (@_) {
		my $key=shift;
		my $value=shift;
		if ($key eq 'tag') {
			push @{$feed->{tags}}, $value;
		}
	}

	return "<a href=\"".$feed->{url}."\">".$feed->{name}."</a>: ".
	       ($feed->{error} ? "<em>" : "").$feed->{message}.
	       ($feed->{error} ? "</em>" : "").
	       " (".$feed->{numposts}." ".gettext("posts").
	       ($feed->{newposts} ? "; ".$feed->{newposts}.
	                            " ".gettext("new") : "").
	       ")";
} # }}}

sub delete (@) { #{{{
	my @files=@_;

	# Remove feed data for removed pages.
	foreach my $file (@files) {
		my $page=pagename($file);
		remove_feeds($page);
	}
} #}}}

my $state_loaded=0;
sub loadstate () { #{{{
	return if $state_loaded;
	$state_loaded=1;
	if (-e "$config{wikistatedir}/aggregate") {
		open(IN, "$config{wikistatedir}/aggregate") ||
			die "$config{wikistatedir}/aggregate: $!";
		while (<IN>) {
			$_=IkiWiki::possibly_foolish_untaint($_);
			chomp;
			my $data={};
			foreach my $i (split(/ /, $_)) {
				my ($field, $val)=split(/=/, $i, 2);
				if ($field eq "name" || $field eq "feed" ||
				    $field eq "guid" || $field eq "message") {
					$data->{$field}=decode_entities($val, " \t\n");
				}
				elsif ($field eq "tag") {
					push @{$data->{tags}}, $val;
				}
				else {
					$data->{$field}=$val;
				}
			}
			
			if (exists $data->{name}) {
				$feeds{$data->{name}}=$data;
			}
			elsif (exists $data->{guid}) {
				$guids{$data->{guid}}=$data;
			}
		}

		close IN;
	}
} #}}}

sub savestate () { #{{{
	return unless $state_loaded;
	eval q{use HTML::Entities};
	error($@) if $@;
	my $newfile="$config{wikistatedir}/aggregate.new";
	my $cleanup = sub { unlink($newfile) };
	open (OUT, ">$newfile") || error("open $newfile: $!", $cleanup);
	foreach my $data (values %feeds, values %guids) {
		if ($data->{remove}) {
			if ($data->{name}) {
				foreach my $guid (values %guids) {
					if ($guid->{feed} eq $data->{name}) {
						$guid->{remove}=1;
					}
				}
			}
			else {
				unlink pagefile($data->{page})
					if exists $data->{page};
			}
			next;
		}
		elsif ($data->{expired} && exists $data->{page}) {
			unlink pagefile($data->{page});
			delete $data->{page};
			delete $data->{md5};
		}

		my @line;
		foreach my $field (keys %$data) {
			if ($field eq "name" || $field eq "feed" ||
			    $field eq "guid" || $field eq "message") {
				push @line, "$field=".encode_entities($data->{$field}, " \t\n");
			}
			elsif ($field eq "tags") {
				push @line, "tag=$_" foreach @{$data->{tags}};
			}
			else {
				push @line, "$field=".$data->{$field};
			}
		}
		print OUT join(" ", @line)."\n" || error("write $newfile: $!", $cleanup);
	}
	close OUT || error("save $newfile: $!", $cleanup);
	rename($newfile, "$config{wikistatedir}/aggregate") ||
		error("rename $newfile: $!", $cleanup);
} #}}}

sub expire () { #{{{
	foreach my $feed (values %feeds) {
		next unless $feed->{expireage} || $feed->{expirecount};
		my $count=0;
		my %seen;
		foreach my $item (sort { $IkiWiki::pagectime{$b->{page}} <=> $IkiWiki::pagectime{$a->{page}} }
		                  grep { exists $_->{page} && $_->{feed} eq $feed->{name} && $IkiWiki::pagectime{$_->{page}} }
		                  values %guids) {
			if ($feed->{expireage}) {
				my $days_old = (time - $IkiWiki::pagectime{$item->{page}}) / 60 / 60 / 24;
				if ($days_old > $feed->{expireage}) {
					debug(sprintf(gettext("expiring %s (%s days old)"),
						$item->{page}, int($days_old)));
					$item->{expired}=1;
				}
			}
			elsif ($feed->{expirecount} &&
			       $count >= $feed->{expirecount}) {
				debug(sprintf(gettext("expiring %s"), $item->{page}));
				$item->{expired}=1;
			}
			else {
				if (! $seen{$item->{page}}) {
					$seen{$item->{page}}=1;
					$count++;
				}
			}
		}
	}
} #}}}

sub aggregate () { #{{{
	eval q{use XML::Feed};
	error($@) if $@;
	eval q{use URI::Fetch};
	error($@) if $@;
	eval q{use HTML::Entities};
	error($@) if $@;

	foreach my $feed (values %feeds) {
		next unless $config{rebuild} || 
			time - $feed->{lastupdate} >= $feed->{updateinterval};
		$feed->{lastupdate}=time;
		$feed->{newposts}=0;
		$feed->{message}=sprintf(gettext("processed ok at %s"),
			displaytime($feed->{lastupdate}));
		$feed->{error}=0;
		$IkiWiki::forcerebuild{$feed->{sourcepage}}=1;

		debug(sprintf(gettext("checking feed %s ..."), $feed->{name}));

		if (! length $feed->{feedurl}) {
			my @urls=XML::Feed->find_feeds($feed->{url});
			if (! @urls) {
				$feed->{message}=sprintf(gettext("could not find feed at %s"), $feed->{url});
				$feed->{error}=1;
				debug($feed->{message});
				next;
			}
			$feed->{feedurl}=pop @urls;
		}
		my $res=URI::Fetch->fetch($feed->{feedurl});
		if (! $res) {
			$feed->{message}=URI::Fetch->errstr;
			$feed->{error}=1;
			debug($feed->{message});
			next;
		}
		if ($res->status == URI::Fetch::URI_GONE()) {
			$feed->{message}=gettext("feed not found");
			$feed->{error}=1;
			debug($feed->{message});
			next;
		}
		my $content=$res->content;
		my $f=eval{XML::Feed->parse(\$content)};
		if ($@) {
			# One common cause of XML::Feed crashing is a feed
			# that contains invalid UTF-8 sequences. Convert
			# feed to ascii to try to work around.
			$feed->{message}.=" ".sprintf(gettext("(invalid UTF-8 stripped from feed)"));
			$content=Encode::decode_utf8($content);
			$f=eval{XML::Feed->parse(\$content)};
		}
		if ($@) {
			# Another possibility is badly escaped entities.
			$feed->{message}.=" ".sprintf(gettext("(feed entities escaped)"));
			$content=~s/\&(?!amp)(\w+);/&amp;$1;/g;
			$content=Encode::decode_utf8($content);
			$f=eval{XML::Feed->parse(\$content)};
		}
		if ($@) {
			$feed->{message}=gettext("feed crashed XML::Feed!")." ($@)";
			$feed->{error}=1;
			debug($feed->{message});
			next;
		}
		if (! $f) {
			$feed->{message}=XML::Feed->errstr;
			$feed->{error}=1;
			debug($feed->{message});
			next;
		}

		foreach my $entry ($f->entries) {
			add_page(
				feed => $feed,
				copyright => $f->copyright,
				title => defined $entry->title ? decode_entities($entry->title) : "untitled",
				link => $entry->link,
				content => defined $entry->content->body ? $entry->content->body : "",
				guid => defined $entry->id ? $entry->id : time."_".$feed->name,
				ctime => $entry->issued ? ($entry->issued->epoch || time) : time,
			);
		}
	}
} #}}}

sub add_page (@) { #{{{
	my %params=@_;
	
	my $feed=$params{feed};
	my $guid={};
	my $mtime;
	if (exists $guids{$params{guid}}) {
		# updating an existing post
		$guid=$guids{$params{guid}};
		return if $guid->{expired};
	}
	else {
		# new post
		$guid->{guid}=$params{guid};
		$guids{$params{guid}}=$guid;
		$mtime=$params{ctime};
		$feed->{numposts}++;
		$feed->{newposts}++;

		# assign it an unused page
		my $page=IkiWiki::titlepage($params{title});
		# escape slashes and periods in title so it doesn't specify
		# directory name or trigger ".." disallowing code.
		$page=~s!([/.])!"__".ord($1)."__"!eg;
		$page=$feed->{dir}."/".$page;
		($page)=$page=~/$config{wiki_file_regexp}/;
		if (! defined $page || ! length $page) {
			$page=$feed->{dir}."/item";
		}
		my $c="";
		while (exists $IkiWiki::pagecase{lc $page.$c} ||
		       -e pagefile($page.$c)) {
			$c++
		}

		# Make sure that the file name isn't too long. 
		# NB: This doesn't check for path length limits.
		my $max=POSIX::pathconf($config{srcdir}, &POSIX::_PC_NAME_MAX);
		if (defined $max && length(htmlfn($page)) >= $max) {
			$c="";
			$page=$feed->{dir}."/item";
			while (exists $IkiWiki::pagecase{lc $page.$c} ||
			       -e pagefile($page.$c)) {
				$c++
			}
		}

		$guid->{page}=$page;
		debug(sprintf(gettext("creating new page %s"), $page));
	}
	$guid->{feed}=$feed->{name};
	
	# To write or not to write? Need to avoid writing unchanged pages
	# to avoid unneccessary rebuilding. The mtime from rss cannot be
	# trusted; let's use a digest.
	eval q{use Digest::MD5 'md5_hex'};
	error($@) if $@;
	require Encode;
	my $digest=md5_hex(Encode::encode_utf8($params{content}));
	return unless ! exists $guid->{md5} || $guid->{md5} ne $digest || $config{rebuild};
	$guid->{md5}=$digest;

	# Create the page.
	my $template=template("aggregatepost.tmpl", blind_cache => 1);
	$template->param(title => $params{title})
		if defined $params{title} && length($params{title});
	$template->param(content => htmlescape(htmlabs($params{content}, $feed->{feedurl})));
	$template->param(name => $feed->{name});
	$template->param(url => $feed->{url});
	$template->param(copyright => $params{copyright})
		if defined $params{copyright} && length $params{copyright};
	$template->param(permalink => urlabs($params{link}, $feed->{feedurl}))
		if defined $params{link};
	if (ref $feed->{tags}) {
		$template->param(tags => [map { tag => $_ }, @{$feed->{tags}}]);
	}
	writefile(htmlfn($guid->{page}), $config{srcdir},
		$template->output);

	# Set the mtime, this lets the build process get the right creation
	# time on record for the new page.
	utime $mtime, $mtime, pagefile($guid->{page})
		if defined $mtime && $mtime <= time;
} #}}}

sub htmlescape ($) { #{{{
	# escape accidental wikilinks and preprocessor stuff
	my $html=shift;
	$html=~s/(?<!\\)\[\[/\\\[\[/g;
	return $html;
} #}}}

sub urlabs ($$) { #{{{
	my $url=shift;
	my $urlbase=shift;

	URI->new_abs($url, $urlbase)->as_string;
} #}}}

sub htmlabs ($$) { #{{{
	# Convert links in html from relative to absolute.
	# Note that this is a heuristic, which is not specified by the rss
	# spec and may not be right for all feeds. Also, see Debian
	# bug #381359.
	my $html=shift;
	my $urlbase=shift;

	my $ret="";
	my $p = HTML::Parser->new(api_version => 3);
	$p->handler(default => sub { $ret.=join("", @_) }, "text");
	$p->handler(start => sub {
		my ($tagname, $pos, $text) = @_;
		if (ref $HTML::Tagset::linkElements{$tagname}) {
			while (4 <= @$pos) {
				# use attribute sets from right to left
				# to avoid invalidating the offsets
				# when replacing the values
				my($k_offset, $k_len, $v_offset, $v_len) =
					splice(@$pos, -4);
				my $attrname = lc(substr($text, $k_offset, $k_len));
				next unless grep { $_ eq $attrname } @{$HTML::Tagset::linkElements{$tagname}};
				next unless $v_offset; # 0 v_offset means no value
				my $v = substr($text, $v_offset, $v_len);
				$v =~ s/^([\'\"])(.*)\1$/$2/;
				my $new_v=urlabs($v, $urlbase);
				$new_v =~ s/\"/&quot;/g; # since we quote with ""
				substr($text, $v_offset, $v_len) = qq("$new_v");
			}
		}
		$ret.=$text;
	}, "tagname, tokenpos, text");
	$p->parse($html);
	$p->eof;

	return $ret;
} #}}}

sub remove_feeds () { #{{{
	my $page=shift;

	my %removed;
	foreach my $id (keys %feeds) {
		if ($feeds{$id}->{sourcepage} eq $page) {
			$feeds{$id}->{remove}=1;
			$removed{$id}=1;
		}
	}
} #}}}

sub pagefile ($) { #{{{
	my $page=shift;

	return "$config{srcdir}/".htmlfn($page);
} #}}}

sub htmlfn ($) { #{{{
	return shift().".".$config{htmlext};
} #}}}

1
