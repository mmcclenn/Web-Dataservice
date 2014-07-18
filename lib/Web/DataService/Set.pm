#
# Web::DataService::Set
# 
# This module provides a role that is used by 'Web::DataService'.  It implements
# routines for defining and documenting output formats.
# 
# Author: Michael McClennen

use strict;

package Web::DataService::Set;

use Carp 'croak';
use Scalar::Util 'reftype';

use Moo::Role;


our (%SET_DEF) = (value => 'single',
		  maps_to => 'single',
		  disabled => 'single',
		  undocumented => 'single');

# define_map ( name, specification... )
# 
# Define a set of values, with optional value map and documentation.  Such
# sets can be used to define and document acceptable parameter values,
# document data values, and many other uses.
# 
# The names of sets must be unique within a single data service.

sub define_set {

    my $self = shift;
    my $name = shift;
    
    # Make sure the name is unique.
    
    croak "define_set: the first argument must be a valid name"
	unless $self->valid_name($name);
    
    croak "define_set: '$name' was already defined at $self->{valueset}{$name}{defined_at}"
	if ref $self->{valueset}{$name};
    
    # Create a new set object.
    
    my ($package, $filename, $line) = caller;
    
    my $vs = { name => $name,
	       defined_at => "line $line of $filename",
	       value => {},
	       enabled => [],
	       documented => [] };
    
    bless $vs, 'Web::DataService::Set';
    
    $self->{set}{$name} = $vs;
    
    # Then process the records and documentation strings one by one.  Throw an
    # exception if we find an invalid record.
    
    my $doc_node;
    my @doc_lines;
    
    foreach my $item (@_)
    {
	# A scalar is interpreted as a documentation string.
	
	unless ( ref $item )
	{
	    $self->add_doc($vs, $item) if defined $item;
	    next;
	}
	
	# Any item that is not a record or a scalar is an error.
	
	unless ( ref $item && reftype $item eq 'HASH' )
	{
	    croak "define_set: arguments must be records (hash refs) and documentation strings";
	}
	
	# Add the record to the documentation list.
	
	$self->add_doc($vs, $item);
	
	# Check for invalid attributes.
	
	foreach my $k ( keys %$item )
	{
	    croak "define_set: unknown attribute '$k'"
		unless defined $SET_DEF{$k};
	}
	
	# Check that each reord contains an actual value, and that these
	# values do not repeat.
	
	my $value = $item->{value};
	
	croak "define_set: you must specify a nonempty 'value' key in each record"
	    unless defined $value && $value ne '';
	
	croak "define_set: value '$value' cannot be defined twice"
	    if exists $vs->{value}{$value};
	
	# Add the value to the various lists it belongs to, and to the hash
	# containing all defined values.
	
	push @{$vs->{enabled}}, $value unless $item->{disabled};
	$vs->{value}{$value} = $item;
    }
    
    # Finish the documentation for this object.
    
    $self->process_doc($vs);
    
    my $a = 1;	# we can stop here when debugging
}


# set_defined ( name )
# 
# Return true if the given argument is the name of a set that has been defined
# for the current data service, false otherweise.

sub set_defined {
    
    my ($self, $name) = @_;
    
    return ref $self->{set}{$name} eq 'Web::DataService::Set';
}


# valid_set ( name )
# 
# Return a reference to a validator routine (actualy a closure) which will
# accept the list of values defined for the specified set.  If the given name
# does not correspond to any set, the returned routine will reject any value
# it is given.

sub valid_set {

    my ($self, $set_name) = @_;
    
    my $vs = $self->{set}{$set_name};
    
    unless ( ref $vs eq 'Web::DataService::Set' )
    {
	print STDERR "WARNING: unknown set '$set_name'";
	return \&bad_set_validator;
    }
    
    # If there is at least one enabled value for this set, return the
    # appropriate closure.
    
    if ( ref $vs->{enabled} eq 'ARRAY' && @{$vs->{enabled}} )
    {
	return HTTP::Validate::ENUM_VALUE( @{$vs->{enabled}} );
    }
    
    # Otherwise, return a reference to a routine which will always return an
    # error.
    
    return \&bad_set_validator;
}


sub bad_set_validator {

    return { error => "No valid values have been defined for {param}." };
}


# document_set ( set_name )
# 
# Return a string in Pod format documenting the values that were assigned to
# this set.

sub document_set {

    my ($self, $set_name) = @_;
    
    # Look up a set object using the given name.  If none could be found,
    # return an explanatory message.
    
    my $vs = $self->{set}{$set_name};
    
    return "=over\n\n=item I<Could not find the specified set>\n\n=back"
	unless ref $vs eq 'Web::DataService::Set';
    
    return "=over\n\n=item I<The specified set does not contain any documented items>\n\n=back"
	unless ref $vs->{documented} eq 'ARRAY' && @{$vs->{documented}};
    
    # Now return the documentation in Pod format.
    
    my $doc = "=over\n\n";
    
    foreach my $name (@{$vs->{documented}})
    {
	my $rec = $vs->{value}{$name};
	next if $rec->{undocumented};
	
	$doc .= "=item $rec->{value}\n\n";
	$doc .= "$rec->{doc}\n\n" if defined $rec->{doc} && $rec->{doc} ne '';
    }
    
    $doc .= "=back";
    
    return $doc;
}


1;
