# 
# Web::DataService::IRequest
# 
# This is a role whose sole purpose is to be composed into the classes defined
# for the various data service operations.  It defines the public interface 
# to a request object.


package Web::DataService::IRequest;

use Carp 'croak';
use Scalar::Util 'reftype';

use Moo::Role;


# has_output_block ( block_key_or_name )
# 
# Return true if the specified block was selected for this request.

sub has_output_block {
    
    my ($request, $key_or_name) = @_;
    
    return 1 if $request->{block_hash}{$key_or_name};
}


# output_block ( name )
# 
# Return true if the named block is selected for the current request.

sub block_selected {

    return $_[0]->{block_hash}{$_[1]};
}


# select_list ( subst )
# 
# Return a list of strings derived from the 'select' records passed to
# define_output.  The parameter $subst, if given, should be a hash of
# substitutions to be made on the resulting strings.

sub select_list {
    
    my ($self, $subst) = @_;
    
    my @fields = @{$self->{select_list}} if ref $self->{select_list} eq 'ARRAY';
    
    if ( defined $subst && ref $subst eq 'HASH' )
    {
	foreach my $f (@fields)
	{
	    $f =~ s/\$(\w+)/$subst->{$1}/g;
	}
    }
    
    return @fields;
}


# select_hash ( subst )
# 
# Return the same set of strings as select_list, but in the form of a hash.

sub select_hash {

    my ($self, $subst) = @_;
    
    return map { $_ => 1} $self->select_list($subst);
}


# select_string ( subst )
# 
# Return the select list (see above) joined into a comma-separated string.

sub select_string {
    
    my ($self, $subst) = @_;
    
    return join(', ', $self->select_list($subst));    
}


# tables_hash ( )
# 
# Return a hashref whose keys are the values of the 'tables' attributes in
# 'select' records passed to define_output.

sub tables_hash {
    
    my ($self) = @_;
    
    return $self->{tables_hash};
}


# add_table ( name )
# 
# Add the specified name to the table hash.

sub add_table {

    my ($self, $table_name, $real_name) = @_;
    
    if ( defined $real_name )
    {
	if ( $self->{tables_hash}{"\$$table_name"} )
	{
	    $self->{tables_hash}{$real_name} = 1;
	}
    }
    else
    {
	$self->{tables_hash}{$table_name} = 1;
    }
}


# filter_hash ( )
# 
# Return a hashref derived from 'filter' records passed to define_output.

sub filter_hash {
    
    my ($self) = @_;
    
    return $self->{filter_hash};
}


# clean_param ( name )
# 
# Return the cleaned value of the named parameter, or the empty string if it
# doesn't exist.

sub clean_param {
    
    my ($self, $name) = @_;
    
    return '' unless ref $self->{valid};
    return $self->{valid}->value($name) // '';
}


# clean_param_list ( name )
# 
# Return a list of all the cleaned values of the named parameter, or the empty
# list if it doesn't exist.

sub clean_param_list {
    
    my ($self, $name) = @_;
    
    return unless ref $self->{valid};
    my $clean = $self->{valid}->value($name);
    return @$clean if ref $clean eq 'ARRAY';
    return unless defined $clean;
    return $clean;
}


# clean_param_hash ( name )
# 
# Return a hashref whose keys are all of the cleaned values of the named
# parameter, or an empty hashref if it doesn't exist.

sub clean_param_hash {
    
    my ($self, $name) = @_;
    
    return {} unless ref $self->{valid};
    
    my $clean = $self->{valid}->value($name);
    
    if ( ref $clean eq 'ARRAY' )
    {
	return { map { $_ => 1 } @$clean };
    }
    
    elsif ( defined $clean && $clean ne '' )
    {
	return { $clean => 1 };
    }
    
    else
    {
	return {};
    }
}


# param_given ( )
# 
# Return true if the specified parameter was included in this request, whether
# or not it was given a valid value.  Return false otherwise.

sub param_given {

    my ($self, $name) = @_;
    
    return unless ref $self->{valid};
    return exists $self->{valid}{raw}{$name};
}


# output_field_list ( )
# 
# Return the output field list for this request.  This is the actual list, not
# a copy, so it can be manipulated.

sub output_field_list {
    
    my ($self) = @_;
    return $self->{field_list};
}


# debug ( )
# 
# Return true if we are in debug mode.

sub debug {
    
    my ($self) = @_;
    
    return $self->{ds}->debug;
}


# process_record ( record, steps )
# 
# Process the specified record using the specified steps.

sub process_record {
    
    my ($self, $record, $steps) = @_;
    my $ds = $self->{ds};
    
    return $ds->process_record($self, $record, $steps);
}


# result_limit ( )
#
# Return the result limit specified for this request, or undefined if
# it is 'all'.

sub result_limit {
    
    return $_[0]->{result_limit} ne 'all' && $_[0]->{result_limit};
}


# result_offset ( will_handle )
# 
# Return the result offset specified for this request, or zero if none was
# specified.  If the parameter $will_handle is true, then auto-offset is
# suppressed.

sub result_offset {
    
    my ($self, $will_handle) = @_;
    
    $self->{offset_handled} = 1 if $will_handle;
    
    return $self->{result_offset} || 0;
}


# sql_limit_clause ( will_handle )
# 
# Return a string that can be added to an SQL statement in order to limit the
# results in accordance with the parameters specified for this request.  If
# the parameter $will_handle is true, then auto-offset is suppressed.

sub sql_limit_clause {
    
    my ($self, $will_handle) = @_;
    
    $self->{offset_handled} = $will_handle ? 1 : 0;
    
    my $limit = $self->{result_limit};
    my $offset = $self->{result_offset} || 0;
    
    if ( $offset > 0 )
    {
	$offset += 0;
	$limit = $limit eq 'all' ? 100000000 : $limit + 0;
	return "LIMIT $offset,$limit";
    }
    
    elsif ( defined $limit and $limit ne 'all' )
    {
	return "LIMIT " . ($limit + 0);
    }
    
    else
    {
	return '';
    }
}


# sql_count_clause ( )
# 
# Return a string that can be added to an SQL statement to generate a result
# count in accordance with the parameters specified for this request.

sub sql_count_clause {
    
    return $_[0]->{display_counts} ? 'SQL_CALC_FOUND_ROWS' : '';
}


# sql_count_rows ( )
# 
# If we were asked to get the result count, execute an SQL statement that will
# do so.

sub sql_count_rows {
    
    my ($self) = @_;
    
    if ( $self->{display_counts} )
    {
	($self->{result_count}) = $self->{dbh}->selectrow_array("SELECT FOUND_ROWS()");
    }
    
    return $self->{result_count};
}


# set_result_count ( count )
# 
# This method should be called if the backend database does not implement the
# SQL FOUND_ROWS() function.  The database should be queried as to the result
# count, and the resulting number passed as a parameter to this method.

sub set_result_count {
    
    my ($self, $count) = @_;
    
    $self->{result_count} = $count;
}


# add_warning ( message )
# 
# Add a warning message to this request object, which will be returned as part
# of the output.

sub add_warning {

    my $self = shift;
    
    foreach my $m (@_)
    {
	push @{$self->{warnings}}, $m if defined $m && $m ne '';
    }
}


# warnings
# 
# Return any warning messages that have been set for this request object.

sub warnings {

    my ($self) = @_;
    
    return unless ref $self->{warnings} eq 'ARRAY';
    return @{$self->{warnings}};
}


# display_header
# 
# Return true if we should display optional header material, false
# otherwise.  The text formats respect this setting, but JSON does not.

sub display_header {
    
    return $_[0]->{display_header};
}


# display_datainfo
# 
# Return true if the data soruce should be displayed, false otherwise.

sub display_datainfo {
    
    return $_[0]->{display_datainfo};    
}


# display_counts
# 
# Return true if the result count should be displayed along with the data,
# false otherwise.

sub display_counts {

    return $_[0]->{display_counts};
}


# params_for_display
# 
# Return a list of (parameter, value) pairs for use in constructing response
# headers.  These are the cleaned parameter values, not the raw ones.

sub params_for_display {
    
    my $self = $_[0];
    my $ds = $self->{ds};
    my $validator = $ds->{validator};
    my $rs_name = $self->{ruleset};
    my $path = $self->{path};
    
    # First get the list of all parameters allowed for this result.  We will
    # then go through them in order to ensure a known order of presentation.
    
    my @param_list = $ds->list_ruleset_params($rs_name);
    
    # We skip some of the special parameter names, specifically those that do
    # not affect the content of the result.
    
    my %skip;
    
    $skip{$ds->{special}{datainfo}} = 1 if $ds->{special}{datainfo};
    $skip{$ds->{special}{linebreak}} = 1 if $ds->{special}{linebreak};
    $skip{$ds->{special}{count}} = 1 if $ds->{special}{count};
    $skip{$ds->{special}{header}} = 1 if $ds->{special}{header};
    $skip{$ds->{special}{save}} = 1 if $ds->{special}{save};
    
    # Now filter this list.  For each parameter that has a value, add its name
    # and value to the display list.
    
    my @display;
    
    foreach my $p ( @param_list )
    {
	# Skip parameters that don't have a value, or that we have noted above.
	
	next unless defined $self->{clean_params}{$p};
	next if $skip{$p};
	
	# Others get included along with their value(s).
	
	my @values = $self->clean_param_list($p);
	
	push @display, $p, join(q{,}, @values);
    }
    
    return @display;
}


# result_counts
# 
# Return a hashref containing the following values:
# 
# found		the total number of records found by the main query
# returned	the number of records actually returned
# offset	the number of records skipped before the first returned one
# 
# These counts reflect the values given for the 'limit' and 'offset' parameters in
# the request, or whichever substitute parameter names were configured for
# this data service.
# 
# If no counts are available, empty strings are returned for all values.

sub result_counts {

    my ($self) = @_;
    
    # Start with a default hashref with empty fields.  This is what will be returned
    # if no information is available.
    
    my $r = { found => $self->{result_count} // '',
	      returned => $self->{result_count} // '',
	      offset => $self->{result_offset} // '' };
    
    # If no result count was given, just return the default hashref.
    
    return $r unless defined $self->{result_count};
    
    # Otherwise, figure out the start and end of the output window.
    
    my $window_start = defined $self->{result_offset} && $self->{result_offset} > 0 ?
	$self->{result_offset} : 0;
    
    my $window_end = $self->{result_count};
    
    # If the offset and limit together don't stretch to the end of the result
    # set, adjust the window end.
    
    if ( defined $self->{result_limit} && $self->{result_limit} ne 'all' &&
	 $window_start + $self->{result_limit} < $window_end )
    {
	$window_end = $window_start + $self->{result_limit};
    }
    
    # The number of records actually returned is the length of the output
    # window. 
    
    $r->{returned} = $window_end - $window_start;
    
    return $r;
}


# linebreak
# 
# Return the linebreak sequence that should be used for the output of this request.

sub linebreak {

    return $_[0]->{linebreak_cr} ? "\n" : "\r\n";
}



# get_config ( )
# 
# Return a hashref providing access to the configuration directives for this
# data service.

sub get_config {
    
    my ($self) = @_;
    
    return $self->{ds}->get_config;
}


# get_connection ( )
# 
# Get a database handle, assuming that the proper directives are present in
# the config.yml file to allow a connection to be made.

sub get_connection {
    
    my ($self) = @_;
    
    return $self->{dbh} if ref $self->{dbh};
    
    $self->{dbh} = $self->{ds}{backend_plugin}->get_connection($self->{ds});
    return $self->{dbh};
}



# set_cors_header ( arg )
# 
# Set the CORS access control header according to the argument.

sub set_cors_header {

    my ($self, $arg) = @_;
    
    $self->{ds}{foundation_plugin}->set_cors_header($self, $arg);
}


# set_content_type ( type )
# 
# Set the content type according to the argument.

sub set_content_type {
    
    my ($self, $type) = @_;
    
    $self->{ds}{foundation_plugin}->set_content_type($self, $type);
}


# single_result ( record )
# 
# Set the result of this operation to the single specified record.  Any
# previously specified results will be removed.

sub single_result {

    my ($self, $record) = @_;
    
    $self->clear_result;
    return unless defined $record;
    
    croak "single_result: the argument must be a hashref\n"
	unless ref $record && reftype $record eq 'HASH';
    
    $self->{main_record} = $record;
}


# list_result ( record_list )
# 
# Set the result of this operation to the specified list of results.  Any
# previously specified results will be removed.

sub list_result {
    
    my $self = shift;
    
    $self->clear_result;
    return unless @_;
    
    # If we were given a single listref, just use that.
    
    if ( scalar(@_) == 1 && ref $_[0] && reftype $_[0] eq 'ARRAY' )
    {
	$self->{main_result} = $_[0];
	return;
    }
    
    # Otherwise, go through the arguments one by one.
    
    my @result;
    
    while ( my $item = shift )
    {
	next unless defined $item;
	croak "list_result: arguments must be hashrefs or listrefs\n"
	    unless ref $item && (reftype $item eq 'ARRAY' or reftype $item eq 'HASH');
	
	if ( reftype $item eq 'ARRAY' )
	{
	    push @result, @$item;
	}
	
	else
	{
	    push @result, $item;
	}
    }
    
    $self->{main_result} = \@result;
}


# data_result ( data )
# 
# Set the result of this operation to the value of the specified scalar.  Any
# previously specified results will be removed.

sub data_result {
    
    my ($self, $data) = @_;
    
    $self->clear_result;
    return unless defined $data;
    
    croak "data_result: the argument must be either a scalar or a scalar ref\n"
	if ref $data && reftype $data ne 'SCALAR';
    
    $self->{main_data} = ref $data ? $$data : $data;
}


# values_result ( values_list )
# 
# Set the result of this operation to the specified list of data values.  Each
# value should be a scalar.

sub values_result {
    
    my $self = shift;
    
    $self->clear_result;
    
    if ( ref $_[0] eq 'ARRAY' )
    {
	$self->{main_values} = $_[0];
    }
    
    else
    {
	$self->{main_values} = [ @_ ];
    }
}


# sth_result ( sth )
# 
# Set the result of this operation to the specified DBI statement handle.  Any
# previously specified results will be removed.

sub sth_result {
    
    my ($self, $sth) = @_;
    
    $self->clear_result;
    return unless defined $sth;
    
    croak "sth_result: the argument must be an object that implements 'fetchrow_hashref'\n"
	unless ref $sth && $sth->can('fetchrow_hashref');
    
    $self->{main_sth} = $sth;
}


# add_result ( record... )
# 
# Add the specified record(s) to the list of result records for this operation.
# Any result previously specified by any method other than 'add_result' or
# 'list_result' will be cleared.

sub add_result {
    
    my $self = shift;
    
    $self->clear_result unless ref $self->{main_result} eq 'ARRAY';
    return unless @_;
    
    croak "add_result: arguments must be hashrefs\n"
	unless ref $_[0] && reftype $_[0] eq 'HASH';
    
    push @{$self->{main_result}}, @_;
}


# clear_result
# 
# Clear all results that have been specified for this operation.

sub clear_result {
    
    my ($self) = @_;
    
    delete $self->{main_result};
    delete $self->{main_record};
    delete $self->{main_data};
    delete $self->{main_sth};
}


1;
