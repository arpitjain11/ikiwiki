#!/usr/bin/perl
package IkiWiki::Plugin::websetup;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "getsetup", id => "websetup", call => \&getsetup);
	hook(type => "checkconfig", id => "websetup", call => \&checkconfig);
	hook(type => "sessioncgi", id => "websetup", call => \&sessioncgi);
	hook(type => "formbuilder_setup", id => "websetup", 
	     call => \&formbuilder_setup);
} # }}}

sub getsetup () { #{{{
	return
		websetup_force_plugins => {
			type => "string",
			example => [],
			description => "list of plugins that cannot be enabled/disabled via the web interface",
			safe => 0,
			rebuild => 0,
		},
		websetup_show_unsafe => {
			type => "boolean",
			example => 1,
			description => "show unsafe settings, read-only, in web interface?",
			safe => 0,
			rebuild => 0,
		},
} #}}}

sub checkconfig () { #{{{
	if (! exists $config{websetup_show_unsafe}) {
		$config{websetup_show_unsafe}=1;
	}
} #}}}

sub formatexample ($$) { #{{{
	my $example=shift;
	my $value=shift;

	if (defined $value && length $value) {
		return "";
	}
	elsif (defined $example && ! ref $example && length $example) {
		return "<br/ ><small>Example: <tt>$example</tt></small>";
	}
	else {
		return "";
	}
} #}}}

sub showfields ($$$@) { #{{{
	my $form=shift;
	my $plugin=shift;
	my $enabled=shift;

	my @show;
	my %plugininfo;
	while (@_) {
		my $key=shift;
		my %info=%{shift()};

		# skip internal settings
		next if defined $info{type} && $info{type} eq "internal";
		# XXX hashes not handled yet
		next if ref $config{$key} && ref $config{$key} eq 'HASH' || ref $info{example} eq 'HASH';
		# maybe skip unsafe settings
		next if ! $info{safe} && ! ($config{websetup_show_unsafe} && $config{websetup_advanced});
		# maybe skip advanced settings
		next if $info{advanced} && ! $config{websetup_advanced};
		# these are handled specially, so don't show
		next if $key eq 'add_plugins' || $key eq 'disable_plugins';

		if ($key eq 'plugin') {
			%plugininfo=%info;
			next;
		}
		
		push @show, $key, \%info;
	}

	my $plugin_forced=defined $plugin && (! $plugininfo{safe} ||
		(exists $config{websetup_force_plugins} && grep { $_ eq $plugin } @{$config{websetup_force_plugins}}));
	if ($plugin_forced && ! $enabled) {
		# plugin is forced disabled, so skip its configuration
		@show=();
	}

	my %shownfields;
	my %skippedfields;
	my $section=defined $plugin ? $plugin." ".gettext("plugin") : "main";
	
	while (@show) {
		my $key=shift @show;
		my %info=%{shift @show};

		my $description=$info{description};
		if (exists $info{link} && length $info{link}) {
			if ($info{link} =~ /^\w+:\/\//) {
				$description="<a href=\"$info{link}\">$description</a>";
			}
			else {
				$description=htmllink("", "", $info{link}, noimageinline => 1, linktext => $description);
			}
		}

		# multiple plugins can have the same field
		my $name=defined $plugin ? $plugin.".".$key : $key;

		my $value=$config{$key};

		if ($info{safe} && (ref $config{$key} eq 'ARRAY' || ref $info{example} eq 'ARRAY')) {
			push @{$value}, "", ""; # blank items for expansion
		}

		if ($info{type} eq "string") {
			$form->field(
				name => $name,
				label => $description,
				comment => formatexample($info{example}, $value),
				type => "text",
				value => $value,
				size => 60,
				fieldset => $section,
			);
		}
		elsif ($info{type} eq "pagespec") {
			$form->field(
				name => $name,
				label => $description,
				comment => formatexample($info{example}, $value),
				type => "text",
				value => $value,
				size => 60,
				validate => \&IkiWiki::pagespec_valid,
				fieldset => $section,
			);
		}
		elsif ($info{type} eq "integer") {
			$form->field(
				name => $name,
				label => $description,
				comment => formatexample($info{example}, $value),
				type => "text",
				value => $value,
				size => 5,
				validate => '/^[0-9]+$/',
				fieldset => $section,
			);
		}
		elsif ($info{type} eq "boolean") {
			$form->field(
				name => $name,
				label => "",
				type => "checkbox",
				value => $value,
				options => [ [ 1 => $description ] ],
				fieldset => $section,
			);
		}
		
		if (! $info{safe}) {
			$form->field(name => $name, disabled => 1);
			$skippedfields{$name}=1;
		}
		else {
			$shownfields{$name}=[$key, \%info];
		}
	}

	if (defined $plugin && (! $plugin_forced || $config{websetup_advanced})) {
		my $name="enable.$plugin";
		$section="plugins" unless %shownfields || (%skippedfields && $config{websetup_advanced});
		$form->field(
			name => $name,
			label => "",
			type => "checkbox",
			options => [ [ 1 => sprintf(gettext("enable %s?"), $plugin) ] ],
			value => $enabled,
			fieldset => $section,
		);
		if ($plugin_forced) {
			$form->field(name => $name, disabled => 1);
		}
		else {
			$shownfields{$name}=[$name, \%plugininfo];
		}
	}

	return %shownfields;
} #}}}

sub showform ($$) { #{{{
	my $cgi=shift;
	my $session=shift;

	if (! defined $session->param("name") || 
	    ! IkiWiki::is_admin($session->param("name"))) {
		error(gettext("you are not logged in as an admin"));
	}

	eval q{use CGI::FormBuilder};
	error($@) if $@;

	my $form = CGI::FormBuilder->new(
		title => "setup",
		name => "setup",
		header => 0,
		charset => "utf-8",
		method => 'POST',
		javascript => 0,
		reset => 1,
		params => $cgi,
		fieldsets => [
			[main => gettext("main")], 
			[plugins => gettext("plugins")]
		],
		action => $config{cgiurl},
		template => {type => 'div'},
		stylesheet => IkiWiki::baseurl()."style.css",
	);

	if ($form->submitted eq 'Basic Mode') {
		$form->field(name => "showadvanced", type => "hidden", 
			value => 0, force => 1);
	}
	elsif ($form->submitted eq 'Advanced Mode') {
		$form->field(name => "showadvanced", type => "hidden", 
			value => 1, force => 1);
	}
	my $advancedtoggle;
	if ($form->field("showadvanced")) {
		$config{websetup_advanced}=1;
		$advancedtoggle="Basic Mode";
	}
	else {
		$config{websetup_advanced}=0;
		$advancedtoggle="Advanced Mode";
	}

	my $buttons=["Save Setup", $advancedtoggle, "Cancel"];

	IkiWiki::decode_form_utf8($form);
	IkiWiki::run_hooks(formbuilder_setup => sub {
		shift->(form => $form, cgi => $cgi, session => $session,
			buttons => $buttons);
	});
	IkiWiki::decode_form_utf8($form);

	$form->field(name => "do", type => "hidden", value => "setup",
		force => 1);
	my %fields=showfields($form, undef, undef, IkiWiki::getsetup());
	
	# record all currently enabled plugins before all are loaded
	my %enabled_plugins=%IkiWiki::loaded_plugins;

	# per-plugin setup
	require IkiWiki::Setup;
	my %plugins=map { $_ => 1 } IkiWiki::listplugins();
	foreach my $pair (IkiWiki::Setup::getsetup()) {
		my $plugin=$pair->[0];
		my $setup=$pair->[1];

		my %shown=showfields($form, $plugin, $enabled_plugins{$plugin}, @{$setup});
		if (%shown) {
			delete $plugins{$plugin};
			$fields{$_}=$shown{$_} foreach keys %shown;
		}
	}
	
	if ($form->submitted eq "Cancel") {
		IkiWiki::redirect($cgi, $config{url});
		return;
	}
	elsif (($form->submitted eq 'Save Setup' || $form->submitted eq 'Rebuild Wiki') && $form->validate) {
		my %rebuild;
		foreach my $field (keys %fields) {
			if ($field=~/^enable\./) {
				# rebuild is overkill for many plugins,
				# but no good way to tell which
				$rebuild{$field}=1; # TODO only if state changed tho
				# TODO plugin enable/disable
				next;
			}
			
			my %info=%{$fields{$field}->[1]};
			my $key=$fields{$field}->[0];
			my @value=$form->field($field);
			
			if (! $info{safe}) {
	 			error("unsafe field $key"); # should never happen
			}

			next unless @value;
			# Avoid setting fields to empty strings,
			# if they were not set before.
			next if ! defined $config{$key} && ! grep { length $_ } @value;

			if (ref $config{$key} eq "ARRAY" || ref $info{example} eq "ARRAY") {
				if ($info{rebuild} && (! defined $config{$key} || (@{$config{$key}}) != (@value))) {
					$rebuild{$field}=1;
				}
				$config{$key}=\@value;
			}
			elsif (ref $config{$key} || ref $info{example}) {
				error("complex field $key"); # should never happen
			}
			else {
				if ($info{rebuild} && (! defined $config{$key} || $config{$key} ne $value[0])) {
					$rebuild{$field}=1;
				}
				$config{$key}=$value[0];
			}		
		}

		if (%rebuild && $form->submitted eq 'Save Setup') {
			$form->text(gettext("The configuration changes shown below require a wiki rebuild to take effect."));
			foreach my $field ($form->field) {
				next if $rebuild{$field};
				$form->field(name => $field, type => "hidden",
					force => 1);
			}
			$form->reset(0); # doesn't really make sense here
			$buttons=["Rebuild Wiki", "Cancel"];
		}
		else {
			# TODO save to real path
			IkiWiki::Setup::dump("/tmp/s");
			$form->text(gettext("Setup saved."));

			if (%rebuild) {
				# TODO rebuild
			}
		}
	}

	IkiWiki::showform($form, $buttons, $session, $cgi);
} #}}}

sub sessioncgi ($$) { #{{{
	my $cgi=shift;
	my $session=shift;

	if ($cgi->param("do") eq "setup") {
		showform($cgi, $session);
		exit;
	}
} #}}}

sub formbuilder_setup (@) { #{{{
	my %params=@_;

	my $form=$params{form};
	if ($form->title eq "preferences") {
		push @{$params{buttons}}, "Wiki Setup";
		if ($form->submitted && $form->submitted eq "Wiki Setup") {
			showform($params{cgi}, $params{session});
			exit;
		}
	}
} #}}}

1
