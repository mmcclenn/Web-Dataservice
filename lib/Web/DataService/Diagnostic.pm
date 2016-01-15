# 
# Web::DataService::Diagnostic
# 
# This module provides a role that is used by 'Web::DataService'.  It implements
# routines for generating diagnostic output about the data service.
# 
# Author: Michael McClennen

use strict;

package Web::DataService::Diagnostic;

use Carp qw(carp croak);

use Moo::Role;


our ($CWD);

our (%DIAG_PARAM) = ( show => 1, splat => 1 );

# diagnostic_request ( @args )
# 
# Generate diagnostic output requested from the command-line.  This is done by
# running the data service application with the following command-line
# arguments: 
# 
# app_name diag <path> <parameters>
# 
# The path is used to select a data service node, in the same way as if
# responding to a request, and the parameters (using the same syntax as URL
# parameters) specify the exact diagnostic output to be generated.
# 
# Examples:
# 
#     app_name diag /data/records/list 'show=digest'
# 
#     app_name diag /data/ 'show=fields&doc=short'
# 
# The path argument is required, and so is the parameter "show".  The
# parameter string must follow URL parameter syntax, so don't include any
# whitespace around the = and & signs.  Possible values are:
# 
# show=digest
# 
#     Generate a digest of the configuration of one or more data service
#     nodes, serialized into YAML.  This can be saved to a file and then
#     analyzed by a separate program.  The purpose of this functionality is to
#     provide for the generation of a report summarizing the differences
#     between the user interfaces of different data service versions
#     (parameters, responses, formats, vocabularies, etc.), for the purposes
#     of generating change logs and other documentation.  By default, the node
#     specified by the path argument is included in the digest, plus
#     (recursively) every node that it links to.  The digest will also include
#     every output block, set, and ruleset linked by any of the nodes.
#     
#     The following additional parameters are available:
#     
#     node = <pattern>
#    
#         Only include nodes whose path matches the specified string, which
#         may contain the standard shell wildcards * and ?.  You can use this
#         to select a subset of the nodes that would otherwise be included.
# 
# show=fields
# 
#     Generate a report (as unformatted text) that tabulates all of the output
#     field names matching the other parameters.  This functionality can be
#     used to make sure that field names and values are consistent between all
#     of the different data service operations.  The path argument is used only to
#     select which data service to analyze, if the application defines more
#     than one.  Other parameters include:
#     
#     vocab = <vocab>
#     
#         Only report output field names from the specified vocabulary.  If
#         the specified vocabulary has the 'use_field_names' attribute, then
#         the names of the underlying data fields will be used whenever no
#         name was explicitly specified for this vocabulary.
#    
#     name = <pattern>
#     
#         Only report output field names which match the specified pattern.
#         The pattern may contain the standard shell wildcards * and ?.
#    
#     data = <pattern>
#     
#         Only report output field names which are linked to a data field
#         matching the specified pattern.  The pattern may contain the standard
#         shell wildcards * and ?.
#     

sub diagnostic_request {

    my ($ds, $request) = @_;
    
    # Start by getting the request parameters, which will tell us which
    # diagnostic operation was requested.
    
    my $params = $Web::DataService::FOUNDATION->get_params($request);
    
    my $diag = lc $params->{show};
    
    if ( $diag eq 'fields' )
    {
	return $ds->diagnostic_fields($request, $params);
    }
    
    elsif ( $diag eq 'digest' )
    {
	return $ds->diagnostic_digest($request, $params);
    }
    
    else
    {
	print STDERR "Usage: you must specify one of the following: 'show=fieldnames', 'show=digest'.\n";
	return;
    }
}


our (%FIELD_PARAM) = ( name => 1,
		       vocab => 1,
		       data => 1,
		       doc => 1 );

# diagnostic_fields ( request )
# 
# Generate diagnostic information about the output fields defined for this
# data service.  See above for documentation.  The report generated by this
# function is written to standard output, because it is designed to be run
# only from the command-line.

sub diagnostic_fields {
    
    my ($ds, $request, $params) = @_;
    
    # First check the query parameters.
    
    my $bad_param;
    
    foreach my $key ( keys %$params )
    {
	unless ( $DIAG_PARAM{$key} || $FIELD_PARAM{$key} )
	{
	    print STDERR "ERROR: unknown parameter '$key'\n";
	    $bad_param = 1;
	}
    }
    
    return if $bad_param;
    
    my $query_vocab = $params->{vocab};
    my $query_name = &diag_generate_regex($params->{name});
    my $query_field = &diag_generate_regex($params->{data});
    
    if ( $query_vocab and not $ds->{vocab}{$query_vocab} )
    {
	print STDERR "ERROR: vocabulary '$query_vocab' is not defined for this data service.\n";
	return;
    }
    
    my @query;
    
    push @query, "vocab = $query_vocab" if $query_vocab;
    push @query, "name = $params->{name}" if $query_name;
    push @query, "data = $params->{data}" if $query_field;
    
    # Now check each of the output blocks defined for this data service, looking
    # for fields in those blocks that match the query parameters.
    
    my (%by_name);
    
    foreach my $block ( keys %{$ds->{block}} )
    {
	my $output_list = $ds->{block}{$block}{output_list};
	next unless ref $output_list eq 'ARRAY';
	
	# Check all entries in the block's output list.
	
    FIELD:
	foreach my $f ( @$output_list )
	{
	    # Ignore any entry in the output_list that does not correspond to
	    # an output field.
	    
	    next unless ref $f eq 'HASH' && $f->{output};
	    
	    # If an output name was speciied, then ignore any entries whose
	    # 'output' attribute does not match.
	    
	    if ( $query_field )
	    {
		next FIELD if $f->{output} !~ $query_field;
	    }
	    
	    # If a vocabulary was specified, then determine the output name.
	    # Ignore entries which do not have a name under this vocabulary.
	    
	    my (@matches);
	    
	    if ( $query_vocab )
	    {
		my $name = $f->{"${query_vocab}_name"} ||= $f->{name};
		$name ||= $f->{output} if $ds->{vocab}{$query_vocab}{use_field_names};
		
		my $value = $f->{"${query_vocab}_value"} || $f->{value};
		
		next unless defined $name && $name ne '';
		next if $query_name && $name !~ $query_name;
		
		push @matches, [$name, $query_vocab, $value];
	    }
	    
	    # If no vocabulary was specified, then determine the output name
	    # under each available vocabulary.
	    
	    else
	    {
		foreach my $v ( @{$ds->{vocab_list}} )
		{
		    my $name = $f->{"${v}_name"} || $f->{name};
		    $name ||= $f->{output} if $ds->{vocab}{$v}{use_field_names};
		    
		    my $value = $f->{"${v}_value"} || $f->{value};
		    
		    next unless defined $name && $name ne '';
		    next if $query_name && $name !~ $query_name;
		    
		    push @matches, [$name, $v, $value];
		}
	    }
	    
	    # Ignore entries for which we did not find at least one match.
	    
	    next FIELD unless @matches;
	    
	    # If we get to this point, then the entry matches the query so
	    # tabulate it by each name.
	    
	    foreach my $m (@matches)
	    {
		my ($name, $vocab, $value) = @$m;
		my $new = { block => $block, vocab => $vocab, vvalue => $value, %$f };
		
		push @{$by_name{"$vocab:$name"}}, $new;
	    }
	}
    }
    
    # Get the current working directory, so we can trim path names.
    
    require "Cwd.pm"; $CWD = &Cwd::getcwd;
    
    # Go through the entries and compute field widths.
    
    my $options = { doc => $params->{doc}, values => $params->{values} };
    
    my @column_widths = 0 x 5;
    
    foreach my $key ( sort { lc $a cmp lc $b } keys %by_name )
    {
	foreach my $f ( @{$by_name{$key}} )
	{
	    $ds->diag_field_widths($key, $f, $options, \@column_widths);
	}
    }
    
    # Now use this list of rows to print out a report tabulated by field name.
    
    $options->{template} = "    %-$column_widths[0]s %-$column_widths[1]s %-$column_widths[2]s %-$column_widths[3]s\n";
    
    print STDOUT "\n";
    print STDOUT "DIAGNOSTIC: FIELDS       " . join(', ', @query) . "\n";
    print STDOUT "===============================================================================\n\n";
    
    print STDOUT " field name\n\n";
    
    my @headings = qw(field block conditionals definition);
    
    foreach my $i (0..3)
    {
	$headings[$i] = '' unless $column_widths[$i];
    }
    
    print STDOUT sprintf($options->{template}, @headings);
    print STDOUT "\n";
    
    foreach my $key ( sort { lc $a cmp lc $b } keys %by_name )
    {
	my ($vocab, $name) = split qr/:/, $key;
	
	print STDOUT " $vocab : '$name'\n\n";
	
	foreach my $f ( @{$by_name{$key}} )
	{
	    $ds->diag_field_output($name, $f, $options);
	}
	
	print STDOUT "\n";
    }
    
    unless ( keys %by_name )
    {
	print STDOUT "No matching fields were found.\n\n";
    }
}


# diag_field_widths ( name, record, options, widths )
# 
# By repeatedly calling this function for each output record, the maximum
# width for each field will be computed.

sub diag_field_widths {
    
    my ($ds, $name, $record, $options, $widths) = @_;
    
    my ($block, $loc, $output, @conditionals);
    
    $block = $record->{block};
    $loc = $ds->{block_loc}{$block};
    $output = $record->{output};
    
    $loc =~ s{$CWD/}{};
    
    $output .= " \"$record->{vvalue}\"" if defined $record->{vvalue} && $record->{vvalue} ne '';
    
    $widths->[0] = length($output) if !defined $widths->[0] || length($output) > $widths->[0];
    $widths->[1] = length($block) if !defined $widths->[1] || length($block) > $widths->[1];
    
    foreach my $c ( qw(if_block not_block if_vocab not_vocab if_field not_field
		       if_format not_format if_code not_code) )
    {
	my $value = $record->{$c};
	next unless $value;
	
	$value = join(q{, }, @$value) if ref $value eq 'ARRAY';
	my $cond = "$c $value";
	$widths->[2] = length($cond) if !defined $widths->[2] || length($cond) > $widths->[2];
    }
    
    $widths->[3] = length($loc) if !defined $widths->[3] || length($loc) > $widths->[3];
    
    foreach my $i ( 0..4 )
    {
	$widths->[$i] //= '0';
    }
}


# diag_field_output ( name, record, options )
# 
# Generate a description of a single output field and write it to standard
# output.

sub diag_field_output {
    
    my ($ds, $name, $record, $options) = @_;
    
    my ($block, $loc, $output, @conditionals);
    
    $block = $record->{block};
    $loc = $ds->{block_loc}{$block};
    $output = $record->{output};
    
    $loc =~ s{$CWD/}{};
    
    $output .= " \"$record->{vvalue}\"" if defined $record->{vvalue} && $record->{vvalue} ne '';
    
    foreach my $c ( qw(if_block not_block if_vocab not_vocab if_field not_field
		       if_format not_format if_code not_code) )
    {
	my $value = $record->{$c};
	next unless $value;
	
	$value = join(q{, }, @$value) if ref $value eq 'ARRAY';
	push @conditionals, "$c $value";
    }
    
    push @conditionals, '' unless @conditionals;
    
    print STDOUT sprintf($options->{template}, $output, $block, $conditionals[0], $loc);
    
    for ( my $i = 1; $i < @conditionals; $i++ )
    {
	print STDOUT sprintf($options->{template}, '', '>>>', $conditionals[$i], '');
    }
    
    if ( $options->{doc} && defined $record->{doc_string} && $record->{doc_string} ne '' )
    {
	my $doc = $record->{doc_string};
	
	if ( $options->{doc} eq 'long' )
	{
	    $doc =~ s/\n/"\n        "/gs;
	}
	else
	{
	    $doc =~ s/\n.*//s;
	}
	
	print STDOUT "        \"$doc\"\n";
    }
}


# generate_regex ( string )
# 
# Generate a regular expression that will match the given string, with * and ?
# as wildcards.

sub diag_generate_regex {
    
    my ($string) = @_;
    
    return unless defined $string && $string ne '';
    
    $string =~ s/[*]/.*/g;
    $string =~ s/[?]/./g;
    
    return qr{^$string$};
}


our (%DIGEST_PARAM) = ( node => 1 );

# diagnostic_digest ( request, params )
# 
# Generate diagnostic information about the user-level specification of this
# data service: the parameters accepted for each operation and the result
# fields returned.

sub diagnostic_digest {
    
    my ($ds, $request, $params) = @_;
    
    # First check the query parameters.
    
    my $bad_param;
    
    foreach my $key ( keys %$params )
    {
	unless ( $DIAG_PARAM{$key} || $DIGEST_PARAM{$key} )
	{
	    print STDERR "ERROR: unknown parameter '$key'\n";
	    $bad_param = 1;
	}
    }
    
    return if $bad_param;
    
    # Then check the node corresponding to the request path.  If it is an
    # operation node, report the specification of that operation.
    
    my $path = $request->node_path;
    my $node_query = &diag_generate_regex($params->{node});
    my $digest = { };
    
    if ( $node_query )
    {
	$digest->{node_query} = $node_query;
	$digest->{_node_query} = $params->{node};
    }
    
    # Add all of the nodes defined for this data service.
    
    foreach my $p ( sort keys %{$ds->{node_attrs}} )
    {
	$ds->diag_add_node($digest, $p);
    }
    
    # Add values from the data service object.
    
    $ds->diag_add_ds_obj($digest);
    
    # Delete keys that were used only during the digest process.
    
    delete $digest->{node_query};
    
    # Now dump the entire specification as a YAML file.
    
    require "YAML.pm";
    
    binmode(STDOUT, ":utf8");
    print STDOUT YAML::Dump($digest);
}


# diag_add_ds_obj ( digest )
# 
# Add a record to the specified digest object to represent important fields
# from the data service object that are not specific to any node.

sub diag_add_ds_obj {

    my ($ds, $digest) = @_;
    
    $digest->{_wds_version} = $Web::DataService::VERSION;
    
    $digest->{ds}{feature} = { %{$ds->{feature}} } if ref $ds->{feature} eq 'HASH';
    $digest->{ds}{special} = { %{$ds->{special}} } if ref $ds->{special} eq 'HASH';
    $digest->{ds}{special_alias} = { %{$ds->{special_alias}} } if ref $ds->{special_alias} eq 'HASH';
    $digest->{ds}{format} = { %{$ds->{format}} } if ref $ds->{format} eq 'HASH';
    $digest->{ds}{format_list} = [ @{$ds->{format_list}} ] if ref $ds->{format_list} eq 'ARRAY';
    $digest->{ds}{vocab} = { %{$ds->{vocab}} } if ref $ds->{vocab} eq 'HASH';
    $digest->{ds}{vocab_list} = [ @{$ds->{vocab_list}} ] if ref $ds->{vocab_list} eq 'ARRAY';
    
    foreach my $key ( qw( name title version path_prefix path_re ruleset_prefix
			  data_source data_provider data_license license_url
			  contact_name contact_email ) )
    {
	$digest->{ds}{$key} = $ds->{$key};
    }
}


# diag_add_node ( digest, path, options )
# 
# Add a record to the specified digest object to represent the specified
# node. Then recursively add records to represent all of the other objects
# (nodes, output blocks, sets, rulesets) linked to it.

sub diag_add_node {
    
    my ($ds, $digest, $path) = @_;
    
    # First do some basic checks.  Return without doing anything unless we
    # have an actual path, and return immediately if we have already added
    # this path.
    
    return unless defined $path && $path ne '';
    return if $digest->{node}{$path};
    
    # Fail gracefully if this node doesn't exist, by simply returning.  We
    # want to complete the specification as best we can.  The caller is
    # responsible for checking and adding and error message if necessary.
    
    return unless ref $ds->{node_attrs}{$path};
    
    # If a node query parameter was specified, then only include nodes whose
    # path matches the specified pattern.
    
    if ( ref $digest->{node_query} eq 'Regexp' && $path !~ $digest->{node_query} )
    {
	return;
    }
    
    # Otherwise copy all of the node attributes into a new hash and add it to
    # the specification.
    
    # print STDERR "Added node $path\n";
    
    my $node = { %{$ds->{node_attrs}{$path}} };
    
    $digest->{node}{$path} = $node;
    
    # Then compute some important attributes that might be inherited.
    
    foreach my $key ( qw(disabled undocumented role method arg ruleset output output_label
			 optional_output summary public_access default_format default_limit
			 default_header default_datainfo default_count default_linebreak
			 default_save_filename allow_method allow_format allow_vocab) )
    {
	my $value = $ds->node_attr($path, $key);
	
	if ( defined $value && $value ne '' )
	{
	    $node->{$key} = $value;
	}
    }
    
    # Then compute some other values that might not be specified directly.
    
    $node->{ruleset} ||= $ds->determine_ruleset($path);
    
    if ( my @subnode_list = $ds->get_nodelist($path) )
    {
	# my @subnode_paths = map { $_->{path} } @subnode_list;
	$node->{node_list} = \@subnode_list;
    }
    
    # Then we go through and figure out all of the blocks, sets, and rulesets
    # referenced by this node and add those to the specification as well.
    
    my (@show_list, @block_list);
    
    my @out_list = &diag_list_value($node, 'output');
    
    foreach my $blockname ( @out_list )
    {
	push @block_list, $blockname;
	$ds->diag_add_block($digest, $blockname);
	$ds->diag_add_check($digest, 'block', $blockname, "node '$path': output");
    }
    
    my @summary = &diag_list_value($node, 'summary');
    
    foreach my $blockname ( @summary )
    {
	$ds->diag_add_block($digest, $blockname);
	$ds->diag_add_check($digest, 'block', $blockname, "node '$path': summary");
    }
    
    if ( my $outmap = $node->{optional_output} )
    {
	my $set = $ds->{set}{$outmap};
	
	if ( $ds->diag_add_check($digest, 'set', $outmap, "node '$path': optional_output") )
	{
	    $ds->diag_add_set($digest, $outmap);
	    
	    foreach my $v ( @{$set->{value_list}} )
	    {
		my $vr = $set->{value}{$v};
		
		push @show_list, $vr->{value};
		
		if ( $vr->{maps_to} )
		{
		    push @block_list, $vr->{maps_to};
		    $ds->diag_add_block($digest, $vr->{maps_to});
		    $ds->diag_add_check($digest, 'block', $vr->{maps_to}, "node '$path': optional_output");
		}
	    }
	}
    }
    
    $node->{show_list} = \@show_list;
    $node->{block_list} = \@block_list;
    
    if ( my $rs_name = $node->{ruleset} )
    {
	$ds->diag_add_ruleset($digest, $rs_name);
	$ds->diag_add_check($digest, 'ruleset', $rs_name, "node '$path'");
    }
    
    elsif ( $node->{method} )
    {
	$ds->diag_add_error($digest, "node '$path'", "no ruleset defined for this node");
    }
}


sub diag_list_value {
    
    my ($hash, $field) = @_;
    
    return unless defined $hash->{$field} && $hash->{$field} ne '';
    
    if ( ref $hash->{$field} eq 'ARRAY' )
    {
	return grep { defined $_ && $_ ne '' } @{$hash->{$field}};
    }
    
    else
    {
	return $hash->{$field};
    }
}


# diag_add_subnodes ( digest, path )
# 
# Go through the list of nodes that are in the "node list" associated with the
# specified path, and add them to the digest.  These are the nodes that are
# linked as "subnodes" of the specified path.

sub diag_add_subnodes {
    
    my ($ds, $digest, $path) = @_;
    
    # Do some basic checks.  Return without doing anything unless we have an
    # actual path.
    
    return unless defined $path && $path ne '';
    
    # If there are any nodes listed as subnodes of this path, then add them.
    
    my @subnodes = $ds->get_nodelist($path);
    
    foreach my $n ( @subnodes )
    {
	my $subnode_path = $n->{path};
	$ds->diag_add_node($digest, $subnode_path);
	$ds->diag_add_check($digest, 'node', $subnode_path, "node '$path': subnode list");
    }
}


sub diag_add_block {
    
    my ($ds, $digest, $name) = @_;
    
    # First do some basic checks.  Return without doing anything if we weren't
    # given an actual block name, or if we have already added this block.
    
    return unless defined $name && $name ne '';
    return if $digest->{block}{$name};
    
    # Just as with nodes, fail gracefully if it doesn't exist.
    
    return unless ref $ds->{block}{$name};
    
    # Otherwise copy all of the block attributes into a new hash and add it to
    # the specification.
    
    my $new = { %{$ds->{block}{$name}} };
    
    $digest->{block}{$name} = $new;
    
    # Blocks don't have any other named structures hanging off of them, so we
    # can stop here.
}


sub diag_add_set {

    my ($ds, $digest, $name) = @_;
    
    # First do some basic checks.  Return without doing anything if we weren't
    # given an actual set name, or if we have already added this set.
    
    return unless defined $name && $name ne '';
    return if $digest->{set}{$name};
    
    # Just as with nodes, fail gracefully if it doesn't exist.
    
    return unless ref $ds->{set}{$name};
    
    # Otherwise copy all of the set attributes into a new hash and add it to
    # the specification.
    
    my $new = { %{$ds->{set}{$name}} };
    
    $digest->{set}{$name} = $new;
    
    # Sets don't have any other named structures hanging off of them, so we
    # can stop here.
}


sub diag_add_ruleset {
    
    my ($ds, $digest, $name) = @_;
    
    # First do some basic checks.  Return without doing anything if we weren't
    # given an actual ruleset name, or if we have already added this ruleset.
    
    return unless defined $name && $name ne '';
    return if $digest->{ruleset}{$name};
    
    # Just as with nodes, fail gracefully if it doesn't exist.
    
    my $rs_list = $ds->{ruleset_diag}{$name};
    
    return unless ref $rs_list eq 'ARRAY';
    
    # Otherwise add the ruleset list to the specification.
    
    $digest->{ruleset}{$name} = $rs_list;
    
    # Then go through the rules and add any referenced sets.
    
    foreach my $rule ( @$rs_list )
    {
	next unless ref $rule eq 'HASH';
	
	# First look at the 'valid' field.  This might be an array, so look at
	# each of the values in turn.
	
	my @valid = ref $rule->{valid} eq 'ARRAY' ? @{$rule->{valid}} : $rule->{valid};
	my @new_valid;
	
	foreach my $v (@valid)
	{
	    # If we find a reference, then we must use Perl internal voodoo to
	    # unpack it and figure out the name of whatever it refers to.
	    
	    if ( ref $v )
	    {
		push @new_valid, &diag_decode_ref($v);
	    }
	    
	    # Otherwise, we assume that it is the name of a Set.  So add this
	    # set to the digest unless it's already there.
	    
	    elsif ( $v && $v ne 'FLAG_VALUE' && $v ne 'ANY_VALUE' )
	    {
		$ds->diag_add_set($digest, $v);
		$ds->diag_add_check($digest, 'set', $v, "ruleset'$name'");
		push @new_valid, $v;
	    }
	}
	
	# Now copy this list back to 'valid'.
	
	if ( @new_valid == 1 )
	{
	    $rule->{valid} = $new_valid[0];
	}
	
	elsif ( @new_valid > 1 )
	{
	    $rule->{valid} = \@new_valid;
	}
	
	# If this rule is an inclusion rule, recursively include the target
	# ruleset as well.
	
	my $inclusion = $rule->{allow} || $rule->{require};
	
	if ( $inclusion && ! ref $inclusion )
	{
	    $ds->diag_add_ruleset($digest, $inclusion);
	    $ds->diag_add_check($digest, 'ruleset', $inclusion, "ruleset '$name'");
	}
    }
}


sub diag_decode_ref {
    
    return unless ref $_[0];
    
    my $obj = B::svref_2object $_[0];
    
    return '*UNKNOWN*' unless $obj->can('GV');
    
    my $name = $obj->GV->NAME;
    my $pkg = $obj->GV->STASH->NAME;
    my $sigil = ref $_[0] eq 'CODE'  ? '&'
	      : ref $_[0] eq 'HASH'  ? '%'
	      : ref $_[0] eq 'ARRAY' ? '@'
				     : '?'; 
    
    return "${sigil}${pkg}::${name}";
}


sub diag_add_check {
    
    my ($ds, $digest, $type, $name, $key) = @_;
    
    # Check to see if a proper thingy exists under the proper name.  If so,
    # return true.
    
    my $hashkey = $type;
    $hashkey = 'ruleset_diag' if $type eq 'ruleset';
    $hashkey = 'node_attrs' if $type eq 'node';
    
    return 1 if ref $ds->{$hashkey}{$name};
    
    # Otherwise, add an error to the specification record and return false.
    
    $ds->diag_add_error($digest, $key, "unknown $type '$name'");
    return 0;
}


sub diag_add_error {
    
    my ($ds, $digest, $key, $message) = @_;
    
    return unless defined $message && $message ne '';
    
    $key ||= 'unclassified';
    
    push @{$digest->{errors}{$key}}, $message;
}


1;
