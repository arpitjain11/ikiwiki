#!/usr/bin/perl
package IkiWiki::Plugin::websetup;

use warnings;
use strict;
use IkiWiki 2.00;

my @rcs_plugins=(qw{git svn bzr mercurial monotone tla norcs});

# amazon_s3 is not something that should be enabled via the web.
# external is not a standalone plugin.
my @default_force_plugins=(qw{amazon_s3 external});

sub import { #{{{
	hook(type => "getsetup", id => "websetup", call => \&getsetup);
	hook(type => "sessioncgi", id => "websetup", call => \&sessioncgi);
	hook(type => "formbuilder_setup", id => "websetup", 
	     call => \&formbuilder_setup);
} # }}}

sub getsetup () { #{{{
	return
		websetup_force_plugins => {
			type => "string",
			example => \@default_force_plugins,
			description => "list of plugins that cannot be enabled/disabled via the web interface",
			safe => 0,
			rebuild => 0,
		},
} #}}}

sub formatexample ($) { #{{{
	my $example=shift;

	if (defined $example && ! ref $example && length $example) {
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

		# skip complex, unsafe, or internal settings
		next if ref $config{$key} || ! $info{safe} || $info{type} eq "internal";
		# these are handled specially, so don't show
		next if $key eq 'add_plugins' || $key eq 'disable_plugins';
		
		push @show, $key, \%info;
	}

	return 0 unless @show;

	my $section=defined $plugin ? $plugin." ".gettext("plugin") : gettext("main");

	if (defined $plugin) {
		if (! showplugintoggle($form, $plugin, $enabled, $section) && ! $enabled) {
		    # plugin not enabled and cannot be, so skip showing
		    # its configuration
		    return 0;
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
				comment => defined $value && length $value ? "" : formatexample($info{example}),
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
				comment => formatexample($info{example}),
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
	}

	return 1;
} #}}}

sub showplugintoggle ($$$$) { #{{{
	my $form=shift;
	my $plugin=shift;
	my $enabled=shift;
	my $section=shift;

	if (exists $config{websetup_force_plugins} &&
	    grep { $_ eq $plugin } @{$config{websetup_force_plugins}}, @rcs_plugins) {
		return 0;
	}
	elsif (! exists $config{websetup_force_plugins} &&
	       grep { $_ eq $plugin } @default_force_plugins, @rcs_plugins) {
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
	showfields($form, undef, undef, IkiWiki::getsetup());
	
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

		delete $plugins{$plugin} if showfields($form, $plugin, $enabled_plugins{$plugin}, @{$setup});
	}

	# list all remaining plugins (with no setup options) at the end
	showplugintoggle($form, $_, $enabled_plugins{$_}, gettext("other plugins"))
		foreach sort keys %plugins;
	
	if ($form->submitted eq "Cancel") {
		IkiWiki::redirect($cgi, $config{url});
		return;
	}
	elsif ($form->submitted eq 'Save Setup' && $form->validate) {
		# TODO
		IkiWiki::Setup::dump("/tmp/s");
		$form->text(gettext("Setup saved."));
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
