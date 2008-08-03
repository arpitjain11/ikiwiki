#!/usr/bin/perl
package IkiWiki::Plugin::websetup;

use warnings;
use strict;
use IkiWiki 2.00;

my @rcs_plugins=(qw{git svn bzr mercurial monotone tla norcs});

# amazon_s3 is not something that should be enabled via the web.
# external is not a standalone plugin.
my @force_plugins=(qw{amazon_s3 external});

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
	while (@_) {
		my $key=shift;
		my %info=%{shift()};

		# skip complex or internal settings
		next if ref $config{$key} || ref $info{example} || $info{type} eq "internal";
		# maybe skip unsafe settings
		next if ! $info{safe} && ! $config{websetup_show_unsafe};
		# these are handled specially, so don't show
		next if $key eq 'add_plugins' || $key eq 'disable_plugins';
		
		push @show, $key, \%info;
	}

	return unless @show;

	my $section=defined $plugin ? $plugin." ".gettext("plugin") : gettext("main");

	my %shownfields;
	if (defined $plugin) {
		if (showplugintoggle($form, $plugin, $enabled, $section)) {
			$shownfields{"enable.$plugin"}=[$plugin];
		}
		elsif (! $enabled) {
		    # plugin not enabled and cannot be, so skip showing
		    # its configuration
		    return;
		}
	}

	while (@show) {
		my $key=shift @show;
		my %info=%{shift @show};

		my $description=exists $info{description_html} ? $info{description_html} : $info{description};
		my $value=$config{$key};
		# multiple plugins can have the same field
		my $name=defined $plugin ? $plugin.".".$key : $key;
		
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
			$form->text(gettext("Note: Disabled options cannot be configured here, but only by editing the setup file."));
		}
		else {
			$shownfields{$name}=[$key, \%info];
		}
	}

	return %shownfields;
} #}}}

sub showplugintoggle ($$$$) { #{{{
	my $form=shift;
	my $plugin=shift;
	my $enabled=shift;
	my $section=shift;

	if (exists $config{websetup_force_plugins} &&
	    grep { $_ eq $plugin } @{$config{websetup_force_plugins}}) {
		return 0;
	}
	if (grep { $_ eq $plugin } @force_plugins, @rcs_plugins) {
		return 0;
	}

	$form->field(
		name => "enable.$plugin",
		label => "",
		type => "checkbox",
		options => [ [ 1 => sprintf(gettext("enable %s?"), $plugin) ] ],
		value => $enabled,
		fieldset => $section,
	);

	return 1;
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
		action => $config{cgiurl},
		template => {type => 'div'},
		stylesheet => IkiWiki::baseurl()."style.css",
	);
	my $buttons=["Save Setup", "Cancel"];

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
		
		# skip all rcs plugins except for the one in use
		next if $plugin ne $config{rcs} && grep { $_ eq $plugin } @rcs_plugins;

		my %shown=showfields($form, $plugin, $enabled_plugins{$plugin}, @{$setup});
		if (%shown) {
			delete $plugins{$plugin};
			$fields{$_}=$shown{$_} foreach keys %shown;
		}
	}

	# list all remaining plugins (with no setup options) at the end
	foreach (sort keys %plugins) {
		if (showplugintoggle($form, $_, $enabled_plugins{$_}, gettext("other plugins"))) {
			$fields{"enable.$_"}=[$_];
		}
	}
	
	if ($form->submitted eq "Cancel") {
		IkiWiki::redirect($cgi, $config{url});
		return;
	}
	elsif (($form->submitted eq 'Save Setup' || $form->submitted eq 'Rebuild Wiki') && $form->validate) {
		my %rebuild;
		foreach my $field (keys %fields) {
			# TODO plugin enable/disable
			next if $field=~/^enable\./; # plugin

			my $key=$fields{$field}->[0];
			my %info=%{$fields{$field}->[1]};
			my $value=$form->field($field);

			if (! $info{safe}) {
				error("unsafe field $key"); # should never happen
			}

			next unless defined $value;
			# Avoid setting fields to empty strings,
			# if they were not set before.
			next if ! defined $config{$key} && ! length $value;

			if ($info{rebuild} && (! defined $config{$key} || $config{$key} ne $value)) {
				$rebuild{$field}=1;
			}

			$config{$key}=$value;
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
