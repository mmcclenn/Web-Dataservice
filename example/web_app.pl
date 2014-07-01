#!/usr/bin/perl
# 
# Example Data Service
# 
# This file provides the base application for a data service implemented using
# the Web::DataService framework.
# 
# You can use it as a starting point for setting up your own data service.
# 
# Author: Michael McClennen <mmcclenn@cpan.org>

use strict;

use Dancer;
use Template;

#use Dancer::Plugin::Database;		# You can uncomment this if you wish to
					# use a backend database.

use Web::DataService;


# If we were called from the command line with 'GET' as the first argument,
# then assume that we have been called for debugging purposes.  The second
# argument should be the URL path, and the third should contain any query
# parameters.

if ( defined $ARGV[0] and lc $ARGV[0] eq 'get' )
{
    set apphandler => 'Debug';
    set logger => 'console';
    set show_errors => 0;
    
    Web::DataService->set_mode('debug', 'one_request');
}


# We begin by instantiating a data service object.

my $ds = Web::DataService->new(
    { name => '1.0',
      title => 'Example Data Service',
      path_prefix => 'data1.0',
      doc_templates => 'doc' });


# Continue by defining some output formats.  These are automatically handled
# by the plugins Web::DataService::Plugin::JSON and
# Web::DataService::Plugin::Text.

$ds->define_format(
    { name => 'json', content_type => 'application/json',
      doc_path => 'formats/json', title => 'JSON' },
	"The JSON format is intended primarily to support client applications.",
    { name => 'txt', content_type => 'text/plain',
      doc_path => 'formats/txt', title => 'plain text' },
	"The plain text format is intended for direct responses to users");


# We then define the operation paths that our service will respond to.  The
# path '/' defines a set of root attributes that will be inherited by all
# other path nodes.

$ds->define_path({ path => '/', 
		   public_access => 1,
		   doc_title => 'Documentation' });

# Any URL path starting with /css indicates a stylesheet file.

$ds->define_path({ path => 'css',
			send_files => 1,
			file_dir => 'css' });

# Some example operations

$ds->define_path({ path => 'hello',
		   class => 'Example',
		   method => 'hello',
		   allow_format => 'json,txt' });

$ds->define_path({ path => 'goodbye',
		   class => 'Example',
		   method => 'goodbye',
		   allow_format => 'json,txt' });

# Some documentation nodes

$ds->define_path({ path => 'format',
		   doc_title => 'Output formats' });

$ds->define_path({ path => 'format/json',
		   doc_title => 'JSON format' });

$ds->define_path({ path => 'format/txt',
		   doc_title => 'Plain text format' });


# Next we configure Dancer $$$

# ============

get qr{ ^ (.*) $ }xs => sub {
    
    my ($path) = splat;
    
    #$DB::single = 1;
    
    my $request = $ds_root->new_request(request, $path);
    return $request->execute;
};

dance;
