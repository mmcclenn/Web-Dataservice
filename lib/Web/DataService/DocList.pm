# 
# Web::DataService::DocList
# 
# Objects in this class represent documentation lists.  Other objects and
# documentation strings can be added to such a list, and a single
# documentation string can later be derived from it.
# 
# A documentation list consists of a list of items representing objects,
# paragraphs and inclusions.  Each object-item represents a thing to be
# documented, and will appear in the POD output as an "=item" followed by the
# documentation text as the item body.  A paragraph-item will appear as a
# regular paragraph in the POD output.  An include-item indicates that the
# specified documentation list should be interpolated into this list when
# documentation is produced.
# 
# The POD output will consist of lists and regular paragraphs.  The idea is to
# think of the output as a single flat item list that is possibly interrupted
# by regular paragraphs and then restarted again.  The necessary =over and
# =back command paragraphs will be generated automatically.  The only way that
# nested lists can occur is if an item body contains =over, =item, =back, etc.
# 
# Any object with the attribute 'undocumented' set will be left out of any
# generated documentation.


use strict;

package Web::DataService::DocList;


use Scalar::Util 'reftype';
use Carp 'croak';

use Moo;
use namespace::clean;


# The name of the documentation list (i.e. what is being documented).

has name => ( is => 'ro', required => 1,
	      isa => \&Web::DataService::_valid_name );

# The type of thing being documented (i.e. 'block', 'format', 'vocab').

has type => ( is => 'ro', required => 1,
	      isa => \&Web::DataService::_valid_name );


sub BUILD {

    my ($self) = @_;
    
    $self->{list} = [];
}



# add_object ( obj, name, key )
# 
# Add a new item to the list to represent the specified object.  The object must
# be a hashref.  The optional key can be an arbitrary string, and can be used
# later for including or excluding the object from generated documentation.

sub add_object {
    
    my ($self, $obj, $key) = @_;
    
    croak "add_item: invalid object '$obj', must be a hashref\n" unless ref $obj && reftype $obj eq 'HASH';
    
    # Create a new item record.
    
    my $item = { obj => $obj };
    
    # If a key was specified, add the 'key' field.  If the object has a 'doc'
    # field, use that for the documentation string.
    
    $item->{key} = $key if defined $key && $key ne '';
    $item->{doc} = defined $obj->{doc} && !ref $obj->{doc} ? $obj->{doc} || "";
    
    # Add the new item to the list.
    
    push @{$self->{list}}, $item;
}


# add_string ( str )
# 
# Add a new string to the list.  In most cases, this will be appended to the
# documentation of the most recently added object.  However, in some cases a
# new item will be added to the list to represent a regular paragraph.

sub add_string {
    
    my ($self, $str) = @_;
    
    croak "add_string: argument must not be a reference\n" if ref $str;
    
    # Check for special characters at the beginning of the string.
    
    if ( $item =~ qr{ ^ ([!^?] | >>?) (.*) }xs )
    {
	# If >>, then add a new text-item on to the list

This will generate an
	# ordinary paragraph starting with the remainder of the line.
		
	if ( $1 eq '>>' )
	{
	    $self->process_doc($node);
	    push @{$node->{doc_pending}}, $2 if $2 ne '';
	}
	
	# If >, then add to the current documentation a blank line
	# (which will cause a new paragraph) followed by the remainder
	# of this line.
	
	elsif ( $1 eq '>' )
	{
	    push @{$node->{doc_pending}}, "\n$2";
	}
	
	# If !, then discard all pending documentation and mark the node as
	# 'undoc'.  This will cause it to be elided from the documentation.
	
	elsif ( $1 eq '!' )
	{
	    $self->process_doc($node, 'undoc');
	}
	
	# If ?, then add the remainder of the line to the documentation.
	# The ! prevents the next character from being interpreted specially.
	
	else
	{
	    push @{$node->{doc_pending}}, $2;
	}
    }
}


# add ( arg )
# 
# The argument $arg may be either a hashref (i.e. an object) or a string.

sub add {
    
    my ($self, $arg, $key) = @_;
    
    return unless defined $arg;
    
    # If the argument is a hashref, add a new item to the list that references
    # this object.
    
    if ( ref $arg && reftype $arg eq 'HASH' )
    {
	
	
    }
    
    # If the argument is a string, either add it to the last item in the
    # list, or create a new text-object if the list is empty.
    
    unless ( ref $arg )
    {
	# If there are items in the list, add it to the last of them.
	
	if ( @{$self->{list}} )
	{
	    $self->{list}[-1]{doc} //= "";
	    $self->{list}[-1]{doc} .= $arg;
	}
	    
	
    }
    
    
}
