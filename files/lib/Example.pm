# 
# Example Data Service
# 
# This file provides the base application for an example data service implemented
# using the Web::DataService framework.
# 
# You can use it as a starting point for setting up your own data service.
# 
# Author: Michael McClennen <mmcclenn@cpan.org>

use strict;

package Example;

use lib '../lib';		# Required for testing.  Remove from production app.

use Dancer ':syntax';		# This module is required for
                                # Web::DataService, until plugins for other
                                # foundation frameworks are written.

#use Dancer::Plugin::Database;  # You can uncomment this if you wish to use a
				# backend database via DBI (the example
				# application does not need it).

eval { require Template; };	# This is required in order to generate
                                # documentation pages.

use Web::DataService;		# Bring in Web::DataService.

use PopulationData;		# Load the code which will implement the
                                # data service operations for this
                                # application.  If you use the current file as
                                # a basis for your own application, replace
                                # this line with your own module or modules.


# If we were called from the command line with at least one argument,
# then assume that we have been called for debugging purposes.  The second
# argument should be a URL path.

if ( defined $ARGV[0] )
{    
    my $cmd = lc $ARGV[0];
    
    # If the first command-line argument specifies an HTTP method
    # (i.e. 'get') then set Dancer's apphandler to 'Debug'.  This will
    # cause Dancer to process a single request using the command-line
    # arguments and then exit.
    
    # In this case, the second argument must be the route path.  The third
    # argument if given should be a query string of the form
    # 'param=value&param=value...'.  This should be quoted, to prevent
    # interpretation by the command shell.  Any subsequent arguments should be
    # of the form 'var=value' and are used to set environment variables that
    # would otherwise be set by Plack from HTTP request headers.
    
    if ( $cmd eq 'get' || $cmd eq 'head' || $cmd eq 'put' || $cmd eq 'post' || $cmd eq 'delete' )
    {
	set apphandler => 'Debug';
	set logger => 'console';
	set show_errors => 0;
	
	Web::DataService->set_mode('debug', 'one_request');
    }
    
    # If the first command-line argument is 'diag' then set a flag to indicate
    # that Web::DataService should print out information about the
    # configuration of this data service application and then exit.  This
    # function can be used to debug the configuration.  The second argument
    # should specify which operation path to request information about;
    # specify the root path for the data service if you want information about
    # the entire configuration.
    
    # This option is deliberately made available only via the command-line
    # for security reasons.
    
    elsif ( $cmd eq 'diag' )
    {
	set apphandler => 'Debug';
	set logger => 'console';
	set show_errors => 0;
	set startup_info => 0;
	
	Web::DataService->set_mode('diagnostic');
	
	# We need to alter the first argument to 'get' so that the Dancer
	# routing algorithm will recognize it.
	
	$ARGV[0] = 'GET';
    }
    
    # Otherwise, if the command-line argument is 'debug' then we run in
    # the regular mode (accepting requests from a network port) but put
    # Web::DataService into debug mode.  This will cause debugging output
    # to be printed to STDERR for eqch requests.
    
    elsif ( $cmd eq 'debug' )
    {
	Web::DataService->set_mode('debug');
    }
    
    else
    {
	die "Unknown option '$cmd'\n";
    }
}


# We begin by instantiating a data service object.

my $ds = Web::DataService->new(
    { name => 'data1.0',
      title => 'Example Data Service',
      features => 'standard',
      special_params => 'standard',
      path_prefix => 'data1.0/' });


# Continue by defining some output formats.  These are automatically handled
# by the plugins Web::DataService::Plugin::JSON and
# Web::DataService::Plugin::Text.

$ds->define_format(
    { name => 'json', doc_node => 'formats/json', title => 'JSON' },
	"The JSON format is intended primarily to support client applications.",
    { name => 'txt', doc_node => 'formats/text', title => 'Plain text' },
	"The plain text format is intended for direct responses to humans,",
	"or for loading into a spreadsheet.  Data is formatted as lines of",
        "comma-separated values.",
    { name => 'csv', doc_node => 'formats/text', title => 'Comma Separated Values' },
	"The csv text format is identical to plain text, except that ",
	"most browsers will offer to save it as a download",
    { name => 'tsv', doc_node => 'formats/text', title => 'Tab Separated Values' },
	"The tsv text format returns data as lines of tab-separated values.",
	"Most browsers will offer to save it as a download.");


# We then define a hierarchy of data service nodes.  These nodes define the
# operations and documentation pages that will be available to users of this
# service.  The node '/' defines a set of root attributes that will be
# inherited by all other nodes.

$ds->define_node({ path => '/', 
		   title => 'Main Documentation',
		   public_access => 1,
		   default_format => 'json',
		   doc_default_template => 'doc_not_found.tt',
		   doc_default_op_template => 'operation.tt',
		   output => 'basic' });

# Any URL path starting with /css indicates a stylesheet file:

$ds->define_node({ path => 'css',
		   file_dir => 'css' });


# Some example operations:

$ds->define_node(
    { path => 'single',
      title => 'Single state',
      place => 1,
      usage => [ "single.json?state=wi",
		 "single.txt?state=tx&show=hist&header=no" ],
      output => 'basic',
      optional_output => 'extra',
      role => 'PopulationData',
      method => 'single' },
	"Returns information about a single U.S. state.",
    { path => 'list',
      title => 'Multiple states',
      place => 2,
      usage => [ "list.json?region=ne&show=total",
		 "list.txt?region=we&show=hist,total&count&datainfo" ],
      output => 'basic',
      optional_output => 'extra',
      role => 'PopulationData',
      method => 'list' },
	"Returns information about all of the states matching specified criteria.",
    { path => 'regions',
      title => 'Regions',
      place => 3,
      usage => "regions.txt",
      output => 'regions',
      role => 'PopulationData',
      method => 'regions' },
	"Returns the list of region codes used by this data set.");


# Add documentation about the various output formats, parameters, etc..

$ds->define_node(
    { path => 'formats',
      title => 'Output formats' },
    { path => 'formats/json',
      title => 'JSON format' },
    { path => 'formats/text',
      title => 'Plain text formats' },
    { path => 'special',
      title => 'Special parameters' });


# Next we configure the Dancer routes that will allow this application to
# respond to various URL paths.  For this simple example, all we
# need is a single route with which to capture all requests.

# This may be all you need even for more complicated applications.  But if the
# node structure of Web::DataService is not sufficient to properly describe
# your application, you are free to add additional routes to process
# certain URLs differently.

any qr{.*} => sub {
    
    return Web::DataService->handle_request(request);
};


# If an error occurs, we want to generate a Web::DataService response rather
# than the default Dancer response.  In order for this to happen, we need the
# following two hooks:

hook on_handler_exception => sub {
    
    var(error => $_[0]);
};

hook after_error_render => sub {
    
    $ds->error_result(var('error'), var('wds_request'));
};

1;
