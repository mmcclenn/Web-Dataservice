# 
# DataService.pm
# 
# This is a framework for building data service applications.
# 
# Author: Michael McClennen <mmcclenn@cpan.org>


use strict;

require 5.012;

=head1 NAME

Web::DataService - a framework for building data service applications for the Web

=head1 VERSION

Version 0.10

=head1 SYNOPSIS

This module provides a framework for you to use in building data service
applications for the World Wide Web.  Such applications sit between a data
storage and retrieval system on one hand and the Web on the other, and fulfill
HTTP-based data requests by fetching the appropriate data from the backend and
expressing it in an output format such as JSON or XML.

Using the methods provided by this module, you start by defining a set of
output formats, output blocks, vocabularies, and parameter rules, followed by
a set of data service operations.  Each of these objects is configured by a
set of attributes, optionally including documentation strings.

You continue by writing one or more classes whose methods will handle the
"meat" of each operation: constructing one or more queries on the backend data
system and fetching the resulting data.  This module then handles the rest of
the work necessary for handling each data service request, including
serializing the result in the appropriate output format.

=cut

use lib '/Users/mmcclenn/Sites/Web-DataService/lib';

package Web::DataService;

our $VERSION = '0.20';

use Carp qw( croak confess );
use Scalar::Util qw( reftype blessed weaken );
use POSIX qw( strftime );
use Try::Tiny;
use Sub::Identify;

use Web::DataService::Node;
use Web::DataService::Set;
use Web::DataService::Format;
use Web::DataService::Vocabulary;
use Web::DataService::Ruleset;
use Web::DataService::Render;
use Web::DataService::Output;
use Web::DataService::Execute;

use Web::DataService::Request;
use Web::DataService::IRequest;
use Web::DataService::IDocument;
use Web::DataService::PodParser;

use Moo;
use namespace::clean;

with 'Web::DataService::Node', 'Web::DataService::Set',
     'Web::DataService::Format', 'Web::DataService::Vocabulary',
     'Web::DataService::Ruleset', 'Web::DataService::Render',
     'Web::DataService::Output', 'Web::DataService::Execute';


our (@CARP_NOT) = qw(Web::DataService::Request Moo);

HTTP::Validate->VERSION(0.35);


our @HTTP_METHOD_LIST = ('GET', 'HEAD', 'POST', 'PUT', 'DELETE');

our @DEFAULT_METHODS = ('GET', 'HEAD');

our %SPECIAL_FEATURE = (format_suffix => 1, documentation => 1, 
			doc_paths => 1, send_files => 1, strict_params => 1, 
			stream_output => 1);

our @FEATURE_STANDARD = ('format_suffix', 'documentation', 'doc_paths', 
			 'send_files', 'strict_params', 'stream_output');

our @FEATURE_ALL = ('format_suffix', 'documentation', 'doc_paths', 
		    'send_files', 'strict_params', 'stream_output');

our %SPECIAL_PARAM = (selector => 'v', format => 'format', path => 'op', 
		      show => 'show', limit => 'limit', offset => 'offset', 
		      count => 'count', vocab => 'vocab', 
		      showsource => 'showsource', linebreak => 'lb', 
		      header => 'header', save => 'save');

our @SPECIAL_STANDARD = ('show', 'limit', 'offset', 'header', 'showsource', 
			 'count', 'vocab', 'linebreak', 'save');

our @SPECIAL_SINGLE = ('selector', 'path', 'format', 'show', 'header', 
		       'showsource', 'vocab', 'linebreak', 'save');

our @SPECIAL_ALL = ('selector', 'path', 'format', 'show', 'limit', 'offset', 
		    'header', 'showsource', 'count', 'vocab', 'linebreak', 
		    'save');

# Execution modes

our ($DEBUG, $ONE_REQUEST, $CHECK_LATER);


# Attributes of a Web::DataService object

has name => ( is => 'ro', required => 1,
	      isa => \&_valid_name );

has parent => ( is => 'ro', init_arg => '_parent' );

has features => ( is => 'ro', required => 1 );

has special_params => ( is => 'ro', required => 1 );

has foundation_plugin => ( is => 'ro' );

has templating_plugin => ( is => 'lazy', builder => sub { $_[0]->_init_value('templating_plugin') } );

has backend_plugin => ( is => 'lazy', builder => sub { $_[0]->_init_value('backend_plugin') } );

has path_prefix => ( is => 'lazy', builder => sub { $_[0]->_init_value('path_prefix') } );

has hostname => ( is => 'lazy', builder => sub { $_[0]->_init_value('hostname') } );

has port => ( is => 'lazy', builder => sub { $_[0]->_init_value('port') } );

has generate_url_hook => ( is => 'rw', isa => \&_code_ref );

has title => ( is => 'lazy', builder => sub { $_[0]->_init_value('title') } );

has label => ( is => 'lazy', builder => sub { $_[0]->_init_value('label') } );

has version => ( is => 'lazy', builder => sub { $_[0]->_init_value('version') } );

has path_re => ( is => 'lazy', builder => sub { $_[0]->_init_value('path_re') } );

has doc_suffix => ( is => 'lazy', builder => sub { $_[0]->_init_value('doc_suffix') } );

has doc_index => ( is => 'lazy', builder => sub { $_[0]->_init_value('doc_index') } );

has doc_template_dir => ( is => 'lazy', builder => sub { $_[0]->_init_value('doc_template_dir') } );

has output_template_dir => ( is => 'lazy', builder => sub { $_[0]->_init_value('output_template_dir') } );

has ruleset_prefix => ( is => 'lazy', builder => sub { $_[0]->_init_value('ruleset_prefix') } );

has no_strict_params => ( is => 'lazy', builder => sub { $_[0]->_init_value('no_strict_params') } );

has public_access => ( is => 'lazy', builder => sub { $_[0]->_init_value('public_access') } );

has doc_defs => ( is => 'lazy', builder => sub { $_[0]->_init_value('doc_defs') } );

has doc_header => ( is => 'lazy', builder => sub { $_[0]->_init_value('doc_header') } );

has doc_footer => ( is => 'lazy', builder => sub { $_[0]->_init_value('doc_footer') } );

has doc_stylesheet => ( is => 'lazy', builder => sub { $_[0]->_init_value('doc_stylesheet') } );

has doc_default_template => ( is => 'lazy', builder => sub { $_[0]->_init_value('doc_default_template') } );

has doc_default_op_template => ( is => 'lazy', builder => sub { $_[0]->_init_value('doc_default_op_template') } );

has default_limit => ( is => 'lazy', builder => sub { $_[0]->_init_value('default_limit') } );

has default_header => ( is => 'lazy', builder => sub { $_[0]->_init_value('default_header') } );

has default_showsource => ( is => 'lazy', builder => sub { $_[0]->_init_value('default_showsource') } );

has default_count => ( is => 'lazy', builder => sub { $_[0]->_init_value('default_count') } );

has default_linebreak => ( is => 'lazy', builder => sub { $_[0]->_init_value('default_linebreak') } );

has stream_threshold => ( is => 'lazy', builder => sub { $_[0]->_init_value('stream_threshold') } );

has data_source => ( is => 'lazy', builder => sub { $_[0]->_init_value('data_source') } );

has data_provider => ( is => 'lazy', builder => sub { $_[0]->_init_value('data_provider') } );

has data_license => ( is => 'lazy', builder => sub { $_[0]->_init_value('data_license') } );

has license_url => ( is => 'lazy', builder => sub { $_[0]->_init_value('license_url') } );

has admin_name => ( is => 'lazy', builder => sub { $_[0]->_init_value('admin_name') } );

has admin_email => ( is => 'lazy', builder => sub { $_[0]->_init_value('admin_email') } );

has validator => ( is => 'ro', init_arg => undef );


# Validator methods for the data service attributes.

sub _valid_name {

    die "not a valid name"
	unless $_[0] =~ qr{ ^ [\w.:][\w.:-]* $ }xs;
}


sub _code_ref {

    die "must be a code ref"
	unless ref $_[0] && reftype $_[0] eq 'CODE';
}


# BUILD ( )
# 
# This method is called automatically after object initialization.

sub BUILD {

    my ($self) = @_;
    
    local($Carp::CarpLevel) = 1;	# We shouldn't have to do this, but
                                        # Moo and Carp don't play well together.
    
    # If no path prefix was defined, make it the empty string.
    
    $self->{path_prefix} //= '';
    
    # Process the feature list
    # ------------------------
    
    # These may be specified either as a listref or as a string with
    # comma-separated values.
    
    my $features_value = $self->features;
    my @features = ref $features_value eq 'ARRAY' ? @$features_value : split /\s*,\s*/, $features_value;
    
 ARG:
    foreach my $o ( @features )
    {
	next unless defined $o && $o ne '';
	
	my $feature_value = 1;
	my $key = $o;
	
	# If 'standard' was specified, enable the standard set of features.
	# (But don't override any that have already been set or cleared
	# explicitly.)
	
	if ( $o eq 'standard' )
	{
	    foreach my $p ( @FEATURE_STANDARD )
	    {
		$self->{feature}{$p} //= 1;
	    }
	    
	    next ARG;
	}
	
	# If we get an argument that looks like 'no_feature', then disable
	# the feature.
	
	elsif ( $o =~ qr{ ^ no_ (\w+) $ }xs )
	{
	    $key = $1;
	    $feature_value = 0;
	}
	
	# Now, complain if the user gives us something unrecognized.
	
	croak "unknown feature '$o'\n" unless $SPECIAL_FEATURE{$key};
	
	# Give this parameter the specified value (either on or off).
	# Parameters not mentioned default to off, unless 'standard' was
	# included.
	
	$self->{feature}{$key} = $feature_value;
    }
    
    # Process the list of special parameters
    # --------------------------------------
    
    # These may be specified either as a listref or as a string with
    # comma-separated values.
    
    my $special_value = $self->special_params;
    my @specials = ref $special_value eq 'ARRAY' ? @$special_value : split /\s*,\s*/, $special_value;
    
 ARG:
    foreach my $s ( @specials )
    {
	next unless defined $s && $s ne '';
	my $key = $s;
	my $name = $SPECIAL_PARAM{$s};
	
	# If 'standard' was specified, enable the "standard" set of parameters
	# with their default names (but don't override any that have already
	# been enabled).
	
	if ( $s eq 'standard' )
	{
	    foreach my $p ( @SPECIAL_STANDARD )
	    {
		$self->{special}{$p} //= $SPECIAL_PARAM{$p};
	    }
	    
	    next ARG;
	}
	
	# If we get an argument that looks like 'no_param', then disable
	# the parameter.
	
	elsif ( $s =~ qr{ ^ no_ (\w+) $ }xs )
	{
	    $key = $1;
	    $name = '';
	}
	
	# If we get an argument that looks like 'param=name', then enable the
	# feature 'param' but use 'name' as the accepted parameter name.
	
	elsif ( $s =~ qr{ ^ (\w+) = (\w+) $ }xs )
	{
	    $key = $1;
	    $name = $2;
	}
	
	# Now, complain if the user gives us something unrecognized, or an
	# invalid parameter name.
	
	croak "unknown special parameter '$key'\n" unless $SPECIAL_PARAM{$key};
	croak "invalid parameter name '$name' - bad character\n" if $name =~ /[^\w]/;
	
	# Enable this parameter with the specified name.
	
	$self->{special}{$key} = $name;
    }
    
    # Make sure there are no feature or special parameter conflicts.
    
    croak "you may not specify the feature 'format_suffix' together with the special parameter 'format'"
	if $self->{feature}{format_suffix} && $self->{special}{format};
    
    $self->{feature}{doc_paths} = 0 unless $self->{feature}{documentation};
    
    # Check and configure the foundation plugin
    # -----------------------------------------
    
    # If a foundation plugin was specified in the initialization, make sure
    # that it is correct.
    
    my $foundation_plugin = $self->foundation_plugin;
    
    if ( $foundation_plugin )
    {
	croak "class '$foundation_plugin' is not a valid foundation plugin: cannot find method '_read_config'\n"
	    unless $foundation_plugin->can('_read_config');
    }
    
    # Otherwise, if 'Dancer.pm' has already been required then install the
    # corresponding plugin.
    
    elsif ( $INC{'Dancer.pm'} )
    {
	require Web::DataService::Plugin::Dancer;
	$self->{foundation_plugin} = 'Web::DataService::Plugin::Dancer';
    }
    
    # Otherwise, we cannot proceed.  Give the user some idea of what to do.
    
    else
    {
	croak "could not find a foundation framework: try adding 'use Dancer;' \
before 'use Web::DataService' (and make sure that Dancer is installed)\n";
    }
    
    # Let the plugin do whatever initialization it needs to.
    
    $self->_plugin_init('foundation_plugin');
    
    # From this point on, we will be able to read the configuration file
    # (assuming that a valid one is present).  So do so.
    
    $self->{foundation_plugin}->read_config($self);
    
    # Check and configure the templating plugin
    # -----------------------------------------
    
    # If a templating plugin was explicitly specified, either in the code
    # or in the configuration file, check that it is valid.
    
    if ( $self->{templating_plugin} )
    {
	my $plugin_name = $self->{templating_plugin} || "''";
	
	croak "$plugin_name is not a valid templating plugin: cannot find method 'render_template'\n"
	    unless $self->{templating_plugin}->can('render_template');
    }
    
    # Otherwise, if 'Template.pm' has already been required then install the
    # corresponding plugin.
    
    elsif ( $INC{'Template.pm'} )
    {
	require Web::DataService::Plugin::TemplateToolkit;
	$self->{templating_plugin} = 'Web::DataService::Plugin::TemplateToolkit';
    }
    
    # Otherwise, templating will not be available.
    
    else
    {
	if ( $self->{feature}{documentation} )
	{
	    warn "WARNING: no templating engine was specified, so documentation pages\n";
	    warn "    and templated output will not be available.\n";
	    $self->{feature}{documentation} = 0;
	    $self->{feature}{doc_paths} = 0;
	}
	
	$self->{templating_plugin} = 'Web::DataService::Plugin::Templating';
    }
    
    # If we have a templating plugin, instantiate it for documentation and
    # output.
    
    if ( defined $self->{templating_plugin} && 
	 $self->{templating_plugin} ne 'Web::DataService::Plugin::Templating' )
    {
	# Let the plugin do whatever initialization it needs to.
	
	$self->_plugin_init('templating_plugin');
	
	# If we weren't given a document template directory, use 'doc' if it
	# exists and is readable.
	
	my $doc_dir = $self->doc_template_dir;
	my $output_dir = $self->output_template_dir;
	
	unless ( defined $doc_dir )
	{
	    my $default = $ENV{PWD} . '/doc';
	    
	    if ( -r $default )
	    {
		$doc_dir = $default;
	    }
	    
	    elsif ( $self->{feature}{documentation} )
	    {
		warn "WARNING: no document template directory was found, so documentation pages\n";
		warn "    will not be available.  Try putting them in the directory 'doc',\n";
		warn "    or specifying the attribute 'doc_template_dir'.\n";
		$self->{feature}{documentation} = 0;
		$self->{feature}{doc_paths} = 0;
	    }
	}
	
	# If we were given a directory for documentation templates, initialize
	# an engine for evaluating them.
	
	if ( $doc_dir )
	{
	    $doc_dir = $ENV{PWD} . '/' . $doc_dir
		unless $doc_dir =~ qr{ ^ / }xs;
	    
	    croak "the documentation template directory '$doc_dir' is not readable: $!\n"
		unless -r $doc_dir;
	    
	    $self->{doc_template_dir} = $doc_dir;
	    
	    $self->{doc_engine} = 
		$self->{templating_plugin}->new_engine($self, { template_dir => $doc_dir });
	    
	    # If the attributes doc_header, doc_footer, etc. were not set,
	    # check for the existence of defaults.
	    
	    my $doc_suffix = $self->{template_suffix} || '';
	    
	    $self->{doc_defs} //= $self->check_doc("doc_defs${doc_suffix}");
	    $self->{doc_header} //= $self->check_doc("doc_header${doc_suffix}");
	    $self->{doc_footer} //= $self->check_doc("doc_footer${doc_suffix}");
	    $self->{doc_default_template} //= $self->check_doc("doc_not_found${doc_suffix}");
	    $self->{doc_default_op_template} //= $self->check_doc("doc_op_template${doc_suffix}");
	}
	
	# we were given a directory for output templates, initialize an
	# engine for evaluating them as well.
    
	if ( $output_dir )
	{
	    $output_dir = $ENV{PWD} . '/' . $output_dir
		unless $output_dir =~ qr{ ^ / }xs;
	    
	    croak "the output template directory '$output_dir' is not readable: $!\n"
		unless -r $output_dir;
	    
	    $self->{output_template_dir} = $output_dir;
	    
	    $self->{output_engine} =
		$self->{templating_plugin}->new_engine($self, { template_dir => $output_dir });
	}
	
	# If no stylesheet URL path was specified, use the default.
	
	$self->{doc_stylesheet} //= $self->generate_url({ type => 'site', path => 'css/dsdoc.css' });
    }
    
    # Check and configure the backend plugin
    # --------------------------------------
    
    # If a backend plugin was explicitly specified, check that it is valid.
    
    if ( $self->{backend_plugin} )
    {
	my $plugin_name = $self->{backend_plugin} || "''";
	
	croak "$plugin_name is not a valid backend plugin: cannot find method 'get_connection'\n"
	    unless $self->{backend_plugin}->can('get_connection');
    }
    
    # Otherwise, if 'Dancer::Plugin::Database' is available then select the
    # corresponding plugin.
    
    elsif ( $INC{'Dancer.pm'} && $INC{'Dancer/Plugin/Database.pm'} )
    {
	$self->{backend_plugin} = 'Web::DataService::Plugin::Dancer';
    }
    
    # Otherwise, we get the stub backend plugin which will throw an exception
    # if called.  If you still wish to access a backend data system, then you
    # must either add code to the various operation methods to explicitly
    # connect to it use one of the available hooks.
    
    else
    {
	$self->{backend_plugin} = 'Web::DataService::Plugin::Backend';
    }
    
    # Let the backend plugin do whatever initialization it needs to.
    
    $self->_plugin_init('backend_plugin');
    
    # Check and set some attributes
    # -----------------------------
    
    # The title must be non-empty, but we can't just label it 'required'
    # because it might be specified in the configuration file.
    
    my $title = $self->title;
    
    croak "you must specify a title, either as a parameter to the data service definition or in the configuration file\n"
	unless defined $title && $title ne '';
    
    # If no path_re was set, generate it from the path prefix.
    
    if ( ! $self->path_re )
    {
	my $prefix = $self->path_prefix;
	
	# If the prefix ends in '/', then generate a regexp that can handle
	# either the prefix as given or the prefix string without the final /
	# and without anything after it.
	
	if ( $prefix =~ qr{ (.*) [/] $ }xs )
	{
	    $self->{path_re} = qr{ ^ [/] $1 (?: [/] (.*) | $ ) }xs;
	}
	
	# Otherwise, generate a regexp that doesn't expect a / before the rest
	# of the path.
	
	else
	{
	    $self->{path_re} = qr{ ^ [/] $prefix (.*) }xs;
	}
    }
    
    # Create a default vocabulary, to be used in case no others are defined.
    
    $self->{vocab} = { 'default' => 
		       { name => 'default', use_field_names => 1, _default => 1, title => 'Default',
			 doc_string => "The default vocabulary consists of the field names from the underlying data." } };
    
    $self->{vocab_list} = [ 'default' ];
    
    # We need to set defaults for 'doc_suffix' and 'index_name' so that we can
    # handle 'doc_paths' if it is enabled.  Application authors can turn
    # either of these off by setting the value to the empty string.
    
    $self->{doc_suffix} //= '_doc';
    $self->{doc_index} //= 'index';
    
    # Compute regexes from these suffixes.
    
    if ( $self->{doc_suffix} && $self->{doc_index} )
    {
	$self->{doc_path_regex} = qr{ ^ ( .* [^/] ) (?: $self->{doc_suffix} | / $self->{doc_index} | / ) $ }xs;
    }
    
    elsif ( $self->{doc_suffix} )
    {
	$self->{doc_path_regex} = qr{ ^ ( .* [^/] ) (?: $self->{doc_suffix} | / ) $ }xs;
    }
    
    elsif ( $self->{doc_index} )
    {
	$self->{doc_path_regex} = qr{ ^ ( .* [^/] ) (?: / $self->{doc_index} | / $ }xs;
    }
    
    # The attribute "default_header" defaults to true unless otherwise
    # specified. 
    
    $self->{default_header} //= 1;
    
    # Create a new HTTP::Validate object so that we can do parameter
    # validations. 
    
    $self->{validator} = HTTP::Validate->new();
    
    $self->{validator}->validation_settings(allow_unrecognized => 1)
	unless $self->{feature}{strict_params};
    
    # Add a few other necessary fields.
    
    $self->{path_defs} = {};
    $self->{node_attrs} = {};
    $self->{attr_cache} = {};
    $self->{format} = {};
    $self->{format_list} = [];
    $self->{subservice} = {};
    $self->{subservice_list} = [];
}


# _init_value ( param )
# 
# Return the initial value for the specified parameter.  If it is already
# present as a direct attribute, return that.  Otherwise, look it up in the
# hash of values from the configuration file.  If those fail, check our parent
# (if we have a parent).

sub _init_value {
    
    my ($self, $param) = @_;
    
    die "empty configuration parameter" unless defined $param && $param ne '';
    
    # First check to see if we have this attribute specified directly.
    # Otherwise, check whether it is in our _config hash.  Otherwise,
    # if we have a parent then check its direct attributes and _config hash.
    # Otherwise, return undefined.
    
    my $ds_name = $self->name;
    
    return $self->{$param} if defined $self->{$param};
    return $self->{_config}{$ds_name}{$param} if defined $self->{_config}{$ds_name}{$param};
    return $self->{parent}->_init_value($param) if defined $self->{parent};
    return $self->{_config}{$param} if defined $self->{_config}{$param};
    
    return;
}


# _plugin_init ( plugin )
# 
# If the specified plugin has an 'initialize_service' method, call it with
# ourselves as the argument.

sub _plugin_init {

    my ($self, $plugin) = @_;
    
    return unless defined $self->{$plugin};
    
    no strict 'refs';
    
    if ( $self->{$plugin}->can('initialize_plugin') && ! ${"$self->{$plugin}::_INITIALIZED"} )
    {
	$self->{$plugin}->initialize_plugin($self);
	${"$self->{$plugin}::_INITIALIZED"} = 1;
    }
    
    if ( defined $self->{$plugin} && $self->{$plugin}->can('initialize_service') )
    {    
	$self->{$plugin}->initialize_service($self);
    }
}


# config_value ( param )
# 
# Return the value (if any) specified for this parameter in the configuration
# file.  If not found, check the configuration for our parent (if we have a
# parent).  This differs from _init_value above in that direct attributes are
# not checked.

sub config_value {

    my ($self, $param) = @_;
    
    die "empty configuration parameter" unless defined $param && $param ne '';
    
    # First check to see whether this parameter is in our _config hash.
    # Otherwise, if we have a parent then check its _config hash.  Otherwise,
    # return undefined.
    
    my $ds_name = $self->name;
    
    return $self->{_config}{$ds_name}{$param} if defined $self->{_config}{$ds_name}{$param};
    return $self->{parent}->config_value($param) if defined $self->{parent};
    return $self->{_config}{$param} if defined $self->{_config}{$param};
    
    return;
}


# has_feature ( name )
# 
# Return true if the given feature is set for this data service, undefined
# otherwise. 

sub has_feature {
    
    my ($self, $name) = @_;
    
    croak "has_feature: unknown feature '$name'\n" unless $SPECIAL_FEATURE{$name};
    return $self->{feature}{$name};
}


# special_param ( name )
# 
# If the given special parameter is enabled for this data service, return the
# parameter name.  Otherwise, return the undefined value.

sub special_param {
    
    my ($self, $name) = @_;
    
    croak "special_param: unknown special parameter '$name'\n" unless $SPECIAL_PARAM{$name};
    return $self->{special}{$name};
}


# valid_name ( name )
# 
# Return true if the given name is valid according to the Web::DataService
# specification, false otherwise.

sub valid_name {
    
    my ($self, $name) = @_;
    
    return 1 if defined $name && !ref $name && $name =~ qr{ ^ [\w][\w.:-]* $ }xs;
    return; # otherwise
}


# define_subservice ( attrs... )
# 
# Define one or more subservices of this data service.  This routine cannot be
# used except as an object method.

sub define_subservice { 

    my ($self) = shift;
    
    my ($last_node);
    
    # Start by determining the class of the parent instance.  This will be
    # used for the subservice as well.
    
    my $class = ref $self;
    
    croak "define_subservice: must be called on an existing data service instance\n"
	unless $class;
    
    # We go through the arguments one by one.  Hashrefs define new
    # subservices, while strings add to the documentation of the subservice
    # whose definition they follow.
    
    foreach my $item (@_)
    {
	# A hashref defines a new subservice.
	
	if ( ref $item eq 'HASH' )
	{
	    $item->{parent} = $self;
	    
	    $last_node = $class->new($item)
		unless defined $item->{disabled};
	}
	
	elsif ( not ref $item )
	{
	    $self->add_node_doc($last_node, $item);
	}
	
	else
	{
	    croak "define_subservice: the arguments must be a list of hashrefs and strings\n";
	}
    }
    
    croak "define_subservice: arguments must include at least one hashref of attributes\n"
	unless $last_node;
    
    return $last_node;
}



sub get_connection {
    
    my ($self) = @_;
    
    croak "get_connection: no backend plugin was loaded\n"
	unless defined $self->{backend_plugin};
    return $self->{backend_plugin}->get_connection($self);
}



sub set_mode {
    
    my ($self, @modes) = @_;
    
    foreach my $mode (@modes)
    {
	if ( $mode eq 'debug' )
	{
	    $DEBUG = 1;
	}
	
	elsif ( $mode eq 'one_request' )
	{
	    $ONE_REQUEST = 1;
	}
	
	elsif ( $mode eq 'late_path_check' )
	{
	    $CHECK_LATER = 1;
	}
    }
}


sub is_mode {

    my ($self, $mode) = @_;
    
    return 1 if $mode eq 'debug' && $DEBUG;
    return 1 if $mode eq 'one_request' && $ONE_REQUEST;
    return 1 if $mode eq 'late_path_check' && $CHECK_LATER;
    return;
}


# generate_url ( attrs )
# 
# Generate a URL according to the specified attributes:
# 
# path		Generates a URL for this exact path (with the proper prefix added)
# 
# operation	Generates an operation URL for the specified data service node
# 
# documentation	Generates a documentation URL for the specified data service node
# 
# format	Specifies the format to be included in the URL
# 
# params	Species the parameters, if any, to be included in the URL
# 
# type		Specifies the type of URL to generate: 'absolute' for an
#		absolute URL, 'relative' for a relative URL, 'site' for
#		a site-relative URL (starts with '/').  Defaults to 'site'.

sub generate_url {

    my $self = shift;
    
    my $attrs = ref $_[0] eq 'HASH' ? $_[0] 
	      : scalar(@_) % 2 == 0 ? { @_ }
				    : croak "generate_url: odd number of arguments";
    
    # If a custom routine was specified for this purpose, call it.
    
    if ( $self->{generate_url_hook} )
    {
	return &{$self->{generate_url_hook}}($self, $attrs);
    }
    
    # Otherwise, construct the URL according to the feature set of this data
    # service.

    my $path = $attrs->{documentation} || $attrs->{operation} || $attrs->{path};
    my $format = $attrs->{format};
    
    croak "generate_url: you must specify a URL path\n" unless $path;
    
    $format = 'html' if $attrs->{documentation} && ! (defined $format && $format eq 'pod');
    
    my @params;
    if ( defined $attrs->{documentation} && ref $attrs->{documentation} eq 'ARRAY' )
    {
	push @params, @{$attrs->{documentation}};
	croak "generate_url: odd number of parameters is not allowed\n"
	    if scalar(@_) % 2;
    }
    
    # First, check if the 'fixed_paths' feature is on.  If so, then the given
    # documentation or operation path is converted to a parameter and the appropriate
    # fixed path is substituted.
    
    if ( $self->{feature}{fixed_paths} )
    {
	if ( $attrs->{documentation} )
	{
	    push @params, $self->{special}{document}, $path unless $path eq '/';
	    $path = $self->{doc_url_path};
	}
	
	elsif ( $attrs->{operation} )
	{
	    push @params, $self->{special}{operation}, $path;
	    $path = $self->{operation_url_path};
	}
    }
    
    # Otherwise, we can assume that the URL paths will reflect the given path.
    # So next, check if the 'format_suffix' feature is on.
    
    if ( $self->{feature}{format_suffix} )
    {
	# If this is a documentation URL, then add the documentation suffix if
	# the "doc_paths" feature is on.  Also add the format.  But not if the
	# path is '/'.
	
	if ( $attrs->{documentation} && $path ne '/' )
	{
	    $path .= $self->{doc_suffix} if $self->{feature}{doc_paths};
	    $path .= ".$format";
	}
	
	# If this is an operation URL, we just add the format if one was
	# specified.
	
	elsif ( $attrs->{operation} )
	{
	    $path .= ".$format" if $format;
	}
	
	# A path URL is not modified.
    }
    
    # Otherwise, if the feature 'doc_paths' is on then we still need to modify
    # the paths.
    
    elsif ( $self->{feature}{doc_paths} )
    {
	if ( $attrs->{documentation} && $path ne '/' )
	{
	    $path .= $self->{doc_suffix};
	}
    }
    
    # If the special parameter 'format' is enabled, then we modify the parameters.
    
    if ( $self->{special}{format} )
    {
	# If this is a documentation URL, then add a format parameter unless
	# the format is either 'html' or empty.
	
	if ( $attrs->{documentation} && $format && $format ne 'html' )
	{
	    push @params, $self->{special}{format}, $format;
	}
	
	# Same if this is an operation URL.
	
	elsif ( $attrs->{operation} )
	{
	    push @params, $self->{special}{format} if $format;
	}
	
	# A path URL is not modified.
    }
    
    # If the path is '/', then turn it into the empty string.
    
    $path = '' if $path eq '/';
    
    # Now assemble the URL and return it.
    
    my $type = $attrs->{type};
    
    my $url = $type eq 'absolute' ? $self->base_url :
	      $type eq 'site'     ? '/'
				  : '';
    
    $url .= $self->{path_prefix} if $self->{path_prefix};
    $url .= $path;
    
    if ( @params )
    {
	$url .= '?';
	
	while ( @params )
	{
	    $url .= shift(@params) . '=' . shift(@params) . '&';
	}
    }
    
    return $url;
}


# node_link ( path, title )
# 
# Generate a link in POD format to the documentation for the given path.  If
# $title is defined, use that as the link title.  Otherwise, if the path has a
# 'doc_title' attribute, use that.
# 
# If something goes wrong, generate a warning and return the empty string.

sub node_link {
    
    my ($self, $path, $title) = @_;
    
    return 'I<L<unknown link|node:/>>' unless defined $path;
    
    # Generate a "node:" link for this path, which will be translated into an
    # actual URL later.
    
    if ( defined $title && $title ne '' )
    {
	return "L<$title|node:$path>";
    }
    
    elsif ( $title = $self->node_attr($path, 'title') )
    {
	return "L<$title|node:$path>";
    }
    
    else
    {
	return "I<L<$path|node:$path>>";
    }
}


# base_url ( )
# 
# Return the base URL for this data service, in the form "http://hostname/".
# If the attribute 'port' was specified for this data service, include that
# too.

sub base_url {
    
    my ($self) = @_;
    
    my $hostname = $self->{hostname} // '';
    my $port = $self->{port} ? ':' . $self->{port} : '';
    
    return "http://${hostname}${port}/";
}


# root_url ( )
# 
# Return the root URL for this data service, in the form
# "http://hostname/prefix/".

sub root_url {

    my ($self) = @_;
    
    my $hostname = $self->{hostname} // '';
    my $port = $self->{port} ? ':' . $self->{port} : '';
    
    return "http://${hostname}${port}/$self->{path_prefix}";
}


# execution_class ( primary_role )
# 
# This method is called to create a class in which we can execute requests.
# We need to create one of these for each primary role used in the
# application.
# 
# This class needs to have two roles composed into it: the first is
# Web::DataService::Request, which provides methods for retrieving the request
# parameters, output fields, etc.; the second is the "primary role", written
# by the application author, which provides methods to implement one or more
# data service operations.  We cannot simply use Web::DataService::Request as
# the base class, as different requests may require composing in different
# primary roles.  We cannot use the primary role as the base class, because
# then any method conflicts would be resolved in favor of the primary role.
# This would compromise the functionality of Web::DataService::Request, which
# needs to be able to call its own methods reliably.
# 
# The best way to handle this seems to be to create a new, empty class and
# then compose in both the primary role and Web::DataService::Request using a
# single 'with' request.  This way, an exception will be thrown if the two
# sets of methods conflict.  This new class will be named using the prefix
# 'REQ::', so that if the primary role is 'Example' then the new class will be
# 'REQ::Example'.
# 
# Any other roles needed by the primary role must also be composed in.  We
# also must check for an 'initialize' method in each of these roles, and call
# it if present.  As a result, we cannot simply rely on transitive composition
# by having the application author use 'with' to include one role inside
# another.  Instead, the role author must indicate additional roles as
# follows: 
# 
#     package MyRole;
#     use Moo::Role;
#     
#     our(@REQUIRES_ROLE) = qw(SubRole1 SubRole2);
# 
# Both the primary role and all required roles will be properly initialized,
# which includes calling their 'initialize' method if one exists.  This will
# be done only once per role, no matter how many contexts it is used in.  Each
# of the subsidiary roles will be composed one at a time into the request
# execution class.

sub execution_class {

    my ($self, $primary_role) = @_;
    
    no strict 'refs';
    
    croak "you must specify a non-empty primary role"
	unless defined $primary_role && $primary_role ne '';
    
    croak "you must first load the module '$primary_role' before using it as a primary role"
	unless $primary_role eq 'DOC' || %{ "${primary_role}::" };
    
    my $request_class = "REQ::$primary_role";
    
    # $DB::single = 1;
    
    # First check to see if this class has already been created.  Return
    # immediately if so.
    
    return $request_class if exists ${ "${request_class}::" }{_CREATED};
    
    # Otherwise create the new class and compose in Web::DataService::Request
    # and the primary role.  Then compose in any secondary roles, one at a time.
    
    my $secondary_roles = "";
    
    foreach my $role ( @{ "${primary_role}::REQUIRES_ROLE" } )
    {
	croak "create_request_class: you must first load the module '$role' \
before using it as a secondary role for '$primary_role'"
	    unless %{ "${role}::" };
	
	$secondary_roles .= "with '$role';\n";
    }
    
    my $string =  " package $request_class;
			use Try::Tiny;
			use Scalar::Util qw(reftype);
			use Carp qw(carp croak);
			use Moo;
			use namespace::clean;
			
			use base 'Web::DataService::Request';
			with 'Web::DataService::IRequest', '$primary_role';
			$secondary_roles
			
			our(\$_CREATED) = 1";
    
    my $result = eval $string;
    
    # Now initialize the primary role, unless of course it has already been
    # initialized.  This will also cause any uninitialized secondary roles to
    # be initialized.
    
    $self->initialize_role($primary_role) unless $primary_role eq 'DOC';
    
    return $request_class;
}


# documentation_class ( primary_role )
# 
# This method is called to create a class in which we can process
# documentation requests.  We need to create one of these for each primary
# role used in the application.
# 
# The reason we need these classes is so that the documentation can call
# methods from the primary role if necessary.

sub documentation_class {

    my ($self, $primary_role) = @_;
    
    no strict 'refs';
    
    croak "you must first load the module '$primary_role' before using it as a primary role"
	if $primary_role && ! %{ "${primary_role}::" };
    
    my $request_class = $primary_role ? "DOC::$primary_role" : "DOC";
    
    # First check to see if this class has already been created.  Return
    # immediately if so.
    
    return $request_class if exists ${ "${request_class}::" }{_CREATED};
    
    # Otherwise create the new class and compose in Web::DataService::Request
    # and the primary role.  Then compose in any secondary roles, one at a time.
    
    my $secondary_roles = "";
    
    foreach my $role ( @{ "${primary_role}::REQUIRES_ROLE" } )
    {
	croak "create_request_class: you must first load the module '$role' \
before using it as a secondary role for '$primary_role'"
	    unless %{ "${role}::" };
	
	$secondary_roles .= "with '$role';\n";
    }
    
    my $string =  " package $request_class;
			use Carp qw(carp croak);
			use Moo;
			use namespace::clean;
			
			use base 'Web::DataService::Request';
			with 'Web::DataService::IDocument', '$primary_role';
			$secondary_roles
			
			our(\$_CREATED) = 1";
    
    my $result = eval $string;
    
    # Now initialize the primary role, unless of course it has already been
    # initialized.  This will also cause any uninitialized secondary roles to
    # be initialized.
    
    $self->initialize_role($primary_role);
    
    return $request_class;
}


# initialize_role ( role )
# 
# This method calls the 'initialize' method of the indicated role, but first
# it recursively processes every role required by that role.  The intialize
# method is only called once per role per execution of this program, no matter
# how many contexts it is used in.

sub initialize_role {
    
    my ($self, $role) = @_;
    
    no strict 'refs';
    
    # If we have already initialized this role, there is nothing else we need
    # to do.
    
    return if ${ "${role}::_INITIALIZED" };
    ${ "${role}::_INITIALIZED" } = 1;
    
    # If this role requires one or more secondary roles, then initialize them
    # first (unless they have already been initialized).
    
    foreach my $required ( @{ "${role}::REQUIRES_ROLE" } )
    {
	$self->initialize_role($required);
    }
    
    # Now, if the role has an initialization routine, call it.  We need to do
    # this after the previous step because this role's initialization routine
    # may depend upon side effects of the required roles' initialization routines.
    
    if ( $role->can('initialize') )
    {
	print STDERR "Initializing $role for data service $self->{name}\n" if $DEBUG || $self->{DEBUG};
	$role->initialize($self);
    }
    
    my $a = 1; # we can stop here when debugging
}


# set_scratch ( key, value )
# 
# Store the specified value in the "scratchpad" for this data service, under
# the specified key.  This can be used to store data, configuration
# information, etc. for later use by data operation methods.

sub set_scratch {
    
    my ($self, $key, $value) = @_;
    
    return unless defined $key && $key ne '';
    
    $self->{scratch}{$key} = $value;
}


# get_scratch ( key, value )
# 
# Retrieve the value corresponding to the specified key from the "scratchpad" for
# this data service.

sub get_scratch {
    
    my ($self, $key, $value) = @_;
    
    return unless defined $key && $key ne '';
    
    return $self->{scratch}{$key};
}


# data_info ( )
# 
# Return the following pieces of information:
# - The name of the data source
# - The license under which the data is made available

sub data_info {
    
    my ($self) = @_;
    
    my $access_time = strftime("%a %F %T GMT", gmtime);
    
    my $title = $self->{title};
    my $data_provider = $self->_init_value('data_provider');
    my $data_source = $self->_init_value('data_source');
    my $data_license = $self->_init_value('license');
    my $license_url = $self->_init_value('license_url');
    my $root_url = $self->root_url;
    
    my $result = { 
	data_provider => $data_provider,
	data_source => $data_source,
	data_license => $data_license,
	license_url => $license_url,
	root_url => $root_url,
	access_time => $access_time };
    
    return $result;
}


sub data_info_keys {
    
    return qw(data_provider data_source data_license license_url
	      documentation_url data_url access_time);
}


# get_base_path ( )
# 
# Return the base path for the current data service, derived from the path
# prefix.  For example, if the path prefix is 'data', the base path is
# '/data/'. 

# sub get_base_path {
    
#     my ($self) = @_;
    
#     my $base = '/';
#     $base .= $self->{path_prefix} . '/'
# 	if defined $self->{path_prefix} && $self->{path_prefix} ne '';
    
#     return $base;
# }


sub debug {

    my ($self) = @_;
    
    return $DEBUG || $self->{DEBUG};
}


=head1 METHODS

=head2 CONFIGURATION

The following methods are used to configure a web data service application.

=head3 new ( { attributes ... } )

Defines a new data service instance.  This is generally the first step in
configuring a web dataservice application.  The available attributes are
described in L<Web::DataService::Attributes>.  The attribute C<name> is
required; the others are optional, and may be specified in the application
configuration file instead.  See L<Web::DataService::Intro> for instructions
on how to set up an application.

=head3 define_subservice ( { attributes ... } )

Defines a new data service instance that will be a sub-service of the base
instance.  You can use this method if you wish to have multiple versions of
your service available, i.e a development version and a stable version.  The
sub-service will inherit all of the attributes of the parent, except those
which are explicitly specified.

=head3 define_vocab ( { attributes ... }, documentation ... )

Defines one or more vocabularies, using the specified attributes and
documentation strings.

=head3 valid_vocab ( )

Returns a code reference which can be used in a parameter rule to accept only
valid vocabulary names.

=head3 define_format ( { attributes ... }, documentation ... )

Defines one or more formats, using the specified attributes and documentation
strings.

=head3 define_path ( { attributes ... } )

Defines a new path, using the specified attributes.  Paths do not (currently)
have associated documentation strings.

=head3 define_ruleset ( ruleset_name, { attributes ... }, documentation ... )

Define a ruleset with the given name, containing the specified rules and
documentation.  The arguments to this method are simply passed on to the
C<define_ruleset> method of L<HTTP::Validate>.

=head3 define_block ( block_name, { attributes ... }, documentation ... )

Define an output block with the given name, containing the specified output
fields and documentation.

=head3 define_set ( set_name, { attributes ... }, documentation ... )

Define a set with the given name, containing the specified values and
documentation.

=head2 EXECUTION

The following methods are available for you to use in the part of your code
that handles incoming requests.

=head3 new_request ( outer, path )

Returns an object from the class Web::DataService::Request, representing a 
request on the specified path.  This request can then be executed (using the
C<execute> method) which, in most cases, is all that is necessary to
completely handle a request.

The parameter C<outer> should be a reference to the object generated by the
underlying Web Application Framework (i.e. L<Dancer>) to represent this
request.  The parameter C<path> should be the path corresponding to the
requested operation.

If the data service instance on which you call this method has defined
sub-services, the appropriate sub-service will be automatically selected.

=head3 set_mode ( mode ... )

Turns on one or more of the following modes.

=over 4

=item debug

Produces additional debugging output to STDERR.

=item one_request

Configures the data service to satisfy one request and then exit.  This is
generally used for testing purposes.

=back

=head3 get_attr ( attribute )

Returns the value of the specified data service attribute.

=head3 node_attr ( path, attribute )

Returns the specified attribute of the specified path, if the specified path
and attribute are both defined.  Return undefined otherwise.  You can use this
to test whether a particular path is in fact defined.

=head3 get_connection ( )

If a backend plugin is available, obtains a connection handle from it.  You can
use this method when initializing your data classes.

=head3 get_config ( )

Returns a hash of configuration values from the application configuration file.

=head2 DOCUMENTATION

The following methods are available for you to use in generating
documentation.  If you use the included documentation templates, you will
probably not need to call them directly.

=head3 document_vocab ( path, { options ... } )

Return a documentation string in POD for the vocabularies that are allowed for
the specified path.  The optional C<options> hash may include the following:

=over 4

=item all

Document all vocabularies, not just those allowed for the path.

=item extended

Include the documentation string for each voabulary.

=back

=head3 document_formats ( path, { options ... } )

Return a string containing documentation in POD for the formats that are
allowed for the specified path.  The optional C<options> hash may include the
following:

=over 4

=item all

Documents all formats, not just those allowed for the path.

=item extended

Includes the documentation string for each format.

=back

=head1 AUTHOR

mmcclenn "at" cpan.org

=head1 BUGS

Please report any bugs or feature requests to C<bug-web-dataservice at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Web-DataService>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 COPYRIGHT & LICENSE

Copyright 2014 Michael McClennen, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut


package Web::DataService::Plugin::Foundation;

sub _read_config { die "no foundation plugin was specified"; }

sub get_request_url { die "no foundation plugin was specified"; }

sub get_base_url { die "no foundation plugin was specified"; }

sub get_params { die "no foundation plugin was specified"; }

sub set_header { die "no foundation plugin was specified"; }

sub set_content_type { die "no foundation plugin was specified"; }


package Web::DataService::Plugin::Templating;

sub intialize_service { die "no templating plugin was specified"; }

sub intialize_engine { die "no templating plugin was specified"; }

sub render_template { die "no templating plugin was specified"; }


package Web::DataService::Plugin::Backend;

sub get_connection { die "get_connection: no backend plugin was specified"; }


1;
