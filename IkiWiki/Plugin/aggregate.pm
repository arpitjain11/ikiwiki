#!/usr/bin/perl
# Feed aggregation plugin.
package IkiWiki::Plugin::aggregate;

use warnings;
use strict;
use IkiWiki 3.00;
use HTML::Parser;
use HTML::Tagset;
use HTML::Entities;
use URI;
use open qw{:utf8 :std};

my %feeds;
my %guids;

sub import {
	hook(type => "getopt", id => "aggregate", call => \&getopt);
	hook(type => "getsetup", id => "aggregate", call => \&getsetup);
	hook(type => "checkconfig", id => "aggregate", call => \&checkconfig);
	hook(type => "needsbuild", id => "aggregate", call => \&needsbuild);
	hook(type => "preprocess", id => "aggregate", call => \&preprocess);
        hook(type => "delete", id => "aggregate", call => \&delete);
	hook(type => "savestate", id => "aggregate", call => \&savestate);
	hook(type => "htmlize", id => "_aggregated", call => \&htmlize);
	if (exists $config{aggregate_webtrigger} && $config{aggregate_webtrigger}) {
		hook(type => "cgi", id => "aggregate", call => \&cgi);
	}
}

sub getopt () {
        eval q{use Getopt::Long};
	error($@) if $@;
        Getopt::Long::Configure('pass_through');
        GetOptions(
		"aggregate" => \$config{aggregate},
		"aggregateinternal!" => \$config{aggregateinternal},
	);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
		aggregateinternal => {
			type => "boolean",
			example => 1,
			description => "enable aggregation to internal pages?",
			safe => 0, # enabling needs manual transition
			rebuild => 0,
		},
		aggregate_webtrigger => {
			type => "boolean",
			example => 0,
			description => "allow aggregation to be triggered via the web?",
			safe => 1,
			rebuild => 0,
		},
}

sub checkconfig () {
	if (! defined $config{aggregateinternal}) {
		$config{aggregateinternal}=1;
	}

	if ($config{aggregate} && ! ($config{post_commit} && 
	                             IkiWiki::commit_hook_enabled())) {
		launchaggregation();
	}
}

sub cgi ($) {
	my $cgi=shift;

	if (defined $cgi->param('do') &&
	    $cgi->param("do") eq "aggregate_webtrigger") {
		$|=1;
		print "Content-Type: text/plain\n\n";
		$config{cgi}=0;
		$config{verbose}=1;
		$config{syslog}=0;
		print gettext("Aggregation triggered via web.")."\n\n";
		if (launchaggregation()) {
			IkiWiki::lockwiki();
			IkiWiki::loadindex();
			require IkiWiki::Render;
			IkiWiki::refresh();
			IkiWiki::saveindex();
		}
		else {
			print gettext("Nothing to do right now, all feeds are up-to-date!")."\n";
		}
		exit 0;
	}
}

sub launchaggregation () {
	# See if any feeds need aggregation.
	loadstate();
	my @feeds=needsaggregate();
	return unless @feeds;
	if (! lockaggregate()) {
		debug("an aggregation process is already running");
		return;
	}
	# force a later rebuild of source pages
	$IkiWiki::forcerebuild{$_->{sourcepage}}=1
		foreach @feeds;

	# Fork a child process to handle the aggregation.
	# The parent process will then handle building the
	# result. This avoids messy code to clear state
	# accumulated while aggregating.
	defined(my $pid = fork) or error("Can't fork: $!");
	if (! $pid) {
		IkiWiki::loadindex();
		# Aggregation happens without the main wiki lock
		# being held. This allows editing pages etc while
		# aggregation is running.
		aggregate(@feeds);

		IkiWiki::lockwiki;
		# Merge changes, since aggregation state may have
		# changed on disk while the aggregation was happening.
		mergestate();
		expire();
		savestate();
		IkiWiki::unlockwiki;
		exit 0;
	}
	waitpid($pid,0);
	if ($?) {
		error "aggregation failed with code $?";
	}

	clearstate();
	unlockaggregate();

	return 1;
}

#  Pages with extension _aggregated have plain html markup, pass through.
sub htmlize (@) {
	my %params=@_;
	return $params{content};
}

# Used by ikiwiki-transition aggregateinternal.
sub migrate_to_internal {
	if (! lockaggregate()) {
		error("an aggregation process is currently running");
	}

	IkiWiki::lockwiki();
	loadstate();
	$config{verbose}=1;

	foreach my $data (values %guids) {
		next unless $data->{page};
		next if $data->{expired};
		
		$config{aggregateinternal} = 0;
		my $oldname = "$config{srcdir}/".htmlfn($data->{page});
		my $oldoutput = $config{destdir}."/".IkiWiki::htmlpage($data->{page});
		
		$config{aggregateinternal} = 1;
		my $newname = "$config{srcdir}/".htmlfn($data->{page});
		
		debug "moving $oldname -> $newname";
		if (-e $newname) {
			if (-e $oldname) {
				error("$newname already exists");
			}
			else {
				debug("already renamed to $newname?");
			}
		}
		elsif (-e $oldname) {
			rename($oldname, $newname) || error("$!");
		}
		else {
			debug("$oldname not found");
		}
		if (-e $oldoutput) {
			require IkiWiki::Render;
			debug("removing output file $oldoutput");
			IkiWiki::prune($oldoutput);
		}
	}
	
	savestate();
	IkiWiki::unlockwiki;
	
	unlockaggregate();
}

sub needsbuild (@) {
	my $needsbuild=shift;
	
	loadstate();

	foreach my $feed (values %feeds) {
		if (exists $pagesources{$feed->{sourcepage}} && 
		    grep { $_ eq $pagesources{$feed->{sourcepage}} } @$needsbuild) {
			# Mark all feeds originating on this page as 
			# not yet seen; preprocess will unmark those that
			# still exist.
			markunseen($feed->{sourcepage});
		}
	}
}

sub preprocess (@) {
	my %params=@_;

	foreach my $required (qw{name url}) {
		if (! exists $params{$required}) {
			error sprintf(gettext("missing %s parameter"), $required)
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
	my $dir=exists $params{dir} ? $params{dir} : $params{page}."/".titlepage($params{name});
	$dir=~s/^\/+//;
	($dir)=$dir=~/$config{wiki_file_regexp}/;
	$feed->{dir}=$dir;
	$feed->{feedurl}=defined $params{feedurl} ? $params{feedurl} : "";
	$feed->{updateinterval}=defined $params{updateinterval} ? $params{updateinterval} * 60 : 15 * 60;
	$feed->{expireage}=defined $params{expireage} ? $params{expireage} : 0;
	$feed->{expirecount}=defined $params{expirecount} ? $params{expirecount} : 0;
        if (exists $params{template}) {
                $params{template}=~s/[^-_a-zA-Z0-9]+//g;
        }
        else {
                $params{template} = "aggregatepost"
        }
	$feed->{template}=$params{template} . ".tmpl";
	delete $feed->{unseen};
	$feed->{lastupdate}=0 unless defined $feed->{lastupdate};
	$feed->{lasttry}=$feed->{lastupdate} unless defined $feed->{lasttry};
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
}

sub delete (@) {
	my @files=@_;

	# Remove feed data for removed pages.
	foreach my $file (@files) {
		my $page=pagename($file);
		markunseen($page);
	}
}

sub markunseen ($) {
	my $page=shift;

	foreach my $id (keys %feeds) {
		if ($feeds{$id}->{sourcepage} eq $page) {
			$feeds{$id}->{unseen}=1;
		}
	}
}

my $state_loaded=0;

sub loadstate () {
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
}

sub savestate () {
	return unless $state_loaded;
	garbage_collect();
	my $newfile="$config{wikistatedir}/aggregate.new";
	my $cleanup = sub { unlink($newfile) };
	open (OUT, ">$newfile") || error("open $newfile: $!", $cleanup);
	foreach my $data (values %feeds, values %guids) {
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
				push @line, "$field=".$data->{$field}
					if defined $data->{$field};
			}
		}
		print OUT join(" ", @line)."\n" || error("write $newfile: $!", $cleanup);
	}
	close OUT || error("save $newfile: $!", $cleanup);
	rename($newfile, "$config{wikistatedir}/aggregate") ||
		error("rename $newfile: $!", $cleanup);
}

sub garbage_collect () {
	foreach my $name (keys %feeds) {
		# remove any feeds that were not seen while building the pages
		# that used to contain them
		if ($feeds{$name}->{unseen}) {
			delete $feeds{$name};
		}
	}

	foreach my $guid (values %guids) {
		# any guid whose feed is gone should be removed
		if (! exists $feeds{$guid->{feed}}) {
			unlink "$config{srcdir}/".htmlfn($guid->{page})
				if exists $guid->{page};
			delete $guids{$guid->{guid}};
		}
		# handle expired guids
		elsif ($guid->{expired} && exists $guid->{page}) {
			unlink "$config{srcdir}/".htmlfn($guid->{page});
			delete $guid->{page};
			delete $guid->{md5};
		}
	}
}

sub mergestate () {
	# Load the current state in from disk, and merge into it
	# values from the state in memory that might have changed
	# during aggregation.
	my %myfeeds=%feeds;
	my %myguids=%guids;
	clearstate();
	loadstate();

	# All that can change in feed state during aggregation is a few
	# fields.
	foreach my $name (keys %myfeeds) {
		if (exists $feeds{$name}) {
			foreach my $field (qw{message lastupdate lasttry
			                      numposts newposts error}) {
				$feeds{$name}->{$field}=$myfeeds{$name}->{$field};
			}
		}
	}

	# New guids can be created during aggregation.
	# It's also possible that guids were removed from the on-disk state
	# while the aggregation was in process. That would only happen if
	# their feed was also removed, so any removed guids added back here
	# will be garbage collected later.
	foreach my $guid (keys %myguids) {
		if (! exists $guids{$guid}) {
			$guids{$guid}=$myguids{$guid};
		}
	}
}

sub clearstate () {
	%feeds=();
	%guids=();
	$state_loaded=0;
}

sub expire () {
	foreach my $feed (values %feeds) {
		next unless $feed->{expireage} || $feed->{expirecount};
		my $count=0;
		my %seen;
		foreach my $item (sort { ($IkiWiki::pagectime{$b->{page}} || 0) <=> ($IkiWiki::pagectime{$a->{page}} || 0) }
		                  grep { exists $_->{page} && $_->{feed} eq $feed->{name} }
		                  values %guids) {
			if ($feed->{expireage}) {
				my $days_old = (time - ($IkiWiki::pagectime{$item->{page}} || 0)) / 60 / 60 / 24;
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
}

sub needsaggregate () {
	return values %feeds if $config{rebuild};
	return grep { time - $_->{lastupdate} >= $_->{updateinterval} } values %feeds;
}

sub aggregate (@) {
	eval q{use XML::Feed};
	error($@) if $@;
	eval q{use URI::Fetch};
	error($@) if $@;

	foreach my $feed (@_) {
		$feed->{lasttry}=time;
		$feed->{newposts}=0;
		$feed->{message}=sprintf(gettext("last checked %s"),
			displaytime($feed->{lasttry}));
		$feed->{error}=0;

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

		# lastupdate is only set if we were able to contact the server
		$feed->{lastupdate}=$feed->{lasttry};

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
			$f=eval {
				$content=Encode::decode_utf8($content, 0);
				XML::Feed->parse(\$content)
			};
		}
		if ($@) {
			# Another possibility is badly escaped entities.
			$feed->{message}.=" ".sprintf(gettext("(feed entities escaped)"));
			$content=~s/\&(?!amp)(\w+);/&amp;$1;/g;
			$f=eval {
				$content=Encode::decode_utf8($content, 0);
				XML::Feed->parse(\$content)
			};
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
			# XML::Feed doesn't work around XML::Atom's bizarre
			# API, so we will. Real unicode strings? Yes please.
			# See [[bugs/Aggregated_Atom_feeds_are_double-encoded]]
			local $XML::Atom::ForceUnicode = 1;

			my $c=$entry->content;
			# atom feeds may have no content, only a summary
			if (! defined $c && ref $entry->summary) {
				$c=$entry->summary;
			}

			add_page(
				feed => $feed,
				copyright => $f->copyright,
				title => defined $entry->title ? decode_entities($entry->title) : "untitled",
				link => $entry->link,
				content => (defined $c && defined $c->body) ? $c->body : "",
				guid => defined $entry->id ? $entry->id : time."_".$feed->{name},
				ctime => $entry->issued ? ($entry->issued->epoch || time) : time,
				base => (defined $c && $c->can("base")) ? $c->base : undef,
			);
		}
	}
}

sub add_page (@) {
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
		my $page=titlepage($params{title});
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
		       -e "$config{srcdir}/".htmlfn($page.$c)) {
			$c++
		}

		# Make sure that the file name isn't too long. 
		# NB: This doesn't check for path length limits.
		my $max=POSIX::pathconf($config{srcdir}, &POSIX::_PC_NAME_MAX);
		if (defined $max && length(htmlfn($page)) >= $max) {
			$c="";
			$page=$feed->{dir}."/item";
			while (exists $IkiWiki::pagecase{lc $page.$c} ||
			       -e "$config{srcdir}/".htmlfn($page.$c)) {
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
	my $template=template($feed->{template}, blind_cache => 1);
	$template->param(title => $params{title})
		if defined $params{title} && length($params{title});
	$template->param(content => wikiescape(htmlabs($params{content},
		defined $params{base} ? $params{base} : $feed->{feedurl})));
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

	if (defined $mtime && $mtime <= time) {
		# Set the mtime, this lets the build process get the right
		# creation time on record for the new page.
		utime $mtime, $mtime, "$config{srcdir}/".htmlfn($guid->{page});
		# Store it in pagectime for expiry code to use also.
		$IkiWiki::pagectime{$guid->{page}}=$mtime;
	}
	else {
		# Dummy value for expiry code.
		$IkiWiki::pagectime{$guid->{page}}=time;
	}
}

sub wikiescape ($) {
	# escape accidental wikilinks and preprocessor stuff
	return encode_entities(shift, '\[\]');
}

sub urlabs ($$) {
	my $url=shift;
	my $urlbase=shift;

	URI->new_abs($url, $urlbase)->as_string;
}

sub htmlabs ($$) {
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
}

sub htmlfn ($) {
	return shift().".".($config{aggregateinternal} ? "_aggregated" : $config{htmlext});
}

my $aggregatelock;

sub lockaggregate () {
	# Take an exclusive lock to prevent multiple concurrent aggregators.
	# Returns true if the lock was aquired.
	if (! -d $config{wikistatedir}) {
		mkdir($config{wikistatedir});
	}
	open($aggregatelock, '>', "$config{wikistatedir}/aggregatelock") ||
		error ("cannot open to $config{wikistatedir}/aggregatelock: $!");
	if (! flock($aggregatelock, 2 | 4)) { # LOCK_EX | LOCK_NB
		close($aggregatelock) || error("failed closing aggregatelock: $!");
		return 0;
	}
	return 1;
}

sub unlockaggregate () {
	return close($aggregatelock) if $aggregatelock;
	return;
}

1
