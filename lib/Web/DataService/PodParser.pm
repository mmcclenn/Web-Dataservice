# 
# PodParser2.pm - a pod-to-html translater subclassed from Pod::Simple
# 

use strict;

package Web::DataService::PodParser;
use Pod::Simple;

our(@ISA) = qw(Pod::Simple);


# new ( options )
# 
# Create a new POD parser, subclassing Pod::Simple.

sub new {

    my ($class, $options) = @_;
    
    # Create a new Pod::Simple parser.  We tell it to accept all targets
    # because Pod::Simple behaves strangely when it encounters targets it
    # doesn't know what to do with.  We turn off the automatically generated
    # errata section, since we will be generating this ourselves.  Finally, we
    # provide it a subroutine that will strip indentation from verbatim blocks
    # according to the indentation on the first line.
    
    my $new = $class->SUPER::new;
    
    $new->accept_target_as_text('wds_nav');
    $new->accept_targets('*');
    $new->no_errata_section(1);
    $new->strip_verbatim_indent(sub {
	my $lines = shift;
	(my $indent = $lines->[0]) =~ s/\S.*//;
	return $indent;
    });
    
    # Decorate the parser with some fields relevant to this subclass.
    
    $new->{wds_fields} = { body => [ '' ], target => [ 'body' ],
			   listlevel => 0, listcol => 0 };
    
    if ( ref $options eq 'HASH' )
    {
	foreach my $k ( keys %$options )
	{
	    $new->{wds_fields}{options}{$k} = $options->{$k};
	}
    }
    
    # Create a secondary parser to handle lines of the form "=for target =head3 title"
    
    # $new->{wds_fields}{secondary} = Pod::Simple->new;
    
    # $new->{wds_fields}{secondary}{wds_fields} = { body => [ '' ], target => [ 'body' ],
    # 						  listlevel => 0, listcol => 0 };
    
    return bless $new;
}


sub _handle_element_start {
    
    my ($parser, $element_name, $attr_hash) = @_;
    
    my $wds = $parser->{wds_fields};
    
    if ( $wds->{options}{debug} )
    {
    	print STDERR "START $element_name";
	
    	foreach my $k (keys %$attr_hash)
    	{
    	    print STDERR " $k=" . $attr_hash->{$k};
    	}
	
    	print STDERR "\n";
    }
    
    if ( $wds->{pending_columns} )
    {
	unless ( $element_name eq 'over-text' )
	{
	    push @{$wds->{errors}}, [ $wds->{header_source_line}, 
		   "improperly placed '=for wds_table_header': must immediately precede '=over'" ];
	    $wds->{header_source_line} = undef;
	    $wds->{table_no_header} = undef;
	    $wds->{pending_columns} = undef;
	}
    }
    
    if ( $element_name eq 'Para' && ! $wds->{listlevel} )
    {
	my $attrs = qq{ class="pod_para"};
	
	if ( $wds->{pending_anchor} )
	{
	    $attrs .= qq{ id="$wds->{pending_anchor}"};
	    $wds->{pending_anchor} = undef;
	}
	
	$parser->add_output_text( qq{\n\n<p$attrs>} );
    }
    
    elsif ( $element_name eq 'Data' )
    {
	# nothing to do here -- treat contents of Data sections as regular
	# text
    }
    
    elsif ( $element_name eq 'Verbatim' )
    {
	$parser->add_output_text( qq{<pre class="pod_verbatim">} );
    }
    
    elsif ( $element_name =~ qr{ ^ head ( \d ) }xs )
    {
	my $level = $1;
	my $attrs = qq{ class="pod_heading"};
	
	if ( $wds->{pending_anchor} )
	{
	    $attrs .= qq{ id="$wds->{pending_anchor}"};
	    $wds->{pending_anchor} = undef;
	}
	
	$parser->add_output_text( qq{\n\n<h$level$attrs>} );
    }
    
    elsif ( $element_name =~ qr{ ^ over-(bullet|number) $ }xs )
    {
	my $tag = $1 eq 'bullet' ? 'ul' : 'ol';
	my $class = $wds->{listlevel} > 1 ? 'pod_list2' : 'pod_list';
	my $attrs = qq{ class="$class"};
	
	if ( $wds->{pending_anchor} )
	{
	    $attrs .= qq{ id="$wds->{pending_anchor}"};
	    $wds->{pending_anchor} = undef;
	}
	
	$parser->add_output_text( qq{\n\n<$tag$attrs>} );
	$wds->{listlevel}++;
    }
    
    elsif ( $element_name =~ qr{ ^ item-(bullet|number) $ }xs )
    {
	my $class = $wds->{listlevel} > 1 ? 'pod_def2' : 'pod_def';
	my $attrs = qq{ class="$class"};
	
	if ( $1 =~ qr{^n}i && defined $attr_hash->{'~orig_content'} && defined $attr_hash->{number} )
	{
	    $attr_hash->{'~orig_content'} =~ qr{ (\d+) }xs;
	    if ( $1 ne $attr_hash->{number} )
	    {
		$attrs .= qq{ value="$1"};
	    }
	}
	
	if ( $wds->{pending_anchor} )
	{
	    $attrs .= qq{ id="$wds->{pending_anchor}"};
	    $wds->{pending_anchor} = undef;
	}
	
	$parser->add_output_text( qq{\n\n<li$attrs>} );
    }
    
    elsif ( $element_name =~ qr{ ^ over-text $ }xs )
    {
	my $tag = $wds->{options}{no_tables} ? 'dl' : 'table';
	my $class = $wds->{listlevel} > 0 ? 'pod_list2' : 'pod_list';
	my $attrs = qq{ class="$class"};
	
	if ( $wds->{pending_anchor} )
	{
	    $attrs .= qq{ id="$wds->{pending_anchor}"};
	    $wds->{pending_anchor} = undef;
	}
	
	$parser->add_output_text( qq{\n\n<$tag$attrs>} );
	
	# If we were given a set of table columns, and the 'no_tables' option
	# was not given, then remember that list for the remainder of the
	# table.  Unless 'no_header' was given, emit the header now.
	
	my $table_def = { n_cols => 0, n_subs => 0 };
	
	$table_def->{no_header} = 1 if $wds->{table_no_header};
	
	if ( $wds->{pending_columns} && ! $wds->{options}{no_tables} ) # $$$
	{
	    my @columns;
	    
	    my $class = $wds->{listlevel} > 0 ? 'pod_th2' : 'pod_th';
	    
	    $parser->add_output_text( qq{\n\n<tr class="$class">} ) unless $table_def->{no_header};
	    
	    foreach my $col ( @{$wds->{pending_columns}} )
	    {
		my $col_def;
		my $attrs = '';
		my $multiplicity = 1;
		
		$table_def->{n_cols}++;
		
		if ( $col =~ qr{ ^ (.+) / ( \d+ ) $ }xs )
		{
		    $col = $1;
		    $attrs = qq{ colspan="$2"};
		    $table_def->{n_subs} += $2;
		    $multiplicity = $2;
		    $table_def->{expect_subheader} = 1;
		}
		
		elsif ( $table_def->{n_subs} )
		{
		    $attrs = qq{ rowspan="2"};
		}
		
		if ( $col =~ qr{ ^ (.*) [*] $ }xs )
		{
		    $col_def = { name => $1, term => 1 };
		    $col = $1;
		}
		
		else
		{
		    $col_def = { name => $col };
		}
		
		push @columns, $col_def foreach 1..$multiplicity;
		
		$parser->add_output_text( qq{<td$attrs>$col</td>} ) unless $table_def->{no_header};
	    }
	    
	    $table_def->{columns} = \@columns;
	    
	    $parser->add_output_text( qq{</tr>\n\n} ) unless $table_def->{no_header};
	}
	
	unshift @{$wds->{table_def}}, $table_def;
	
	$wds->{pending_columns} = undef;
	$wds->{header_source_line} = undef;
	$wds->{table_no_header} = undef;
	
	$wds->{listlevel}++;
	$wds->{listcol} = 0;
    }
    
    elsif ( $element_name =~ qr{ ^ item-text $ }xsi )
    {
	if ( $wds->{listcol} > 0 )
	{
	    if ( $wds->{options}{no_tables} )
	    {
		$parser->add_output_text( qq{\n</dd>} );
	    }
	    
	    elsif ( $wds->{listcol} == 2 )
	    {
		$parser->add_output_text( qq{\n</td></tr>} );
	    }
	}
	
	unshift @{$wds->{body}}, '';
	unshift @{$wds->{target}}, 'item-text';
    }
    
    elsif ( $element_name eq 'Para' && $wds->{listlevel} )
    {
	my $class = $wds->{listlevel} > 1 ? 'pod_def2' : 'pod_def';
	my $attrs = qq{ class="$class"};
	
	if ( $wds->{pending_anchor} )
	{
	    $attrs .= qq{ id="$wds->{pending_anchor}"};
	    $wds->{pending_anchor} = undef;
	}
	
	if ( $wds->{listcol} == 1 )
	{
	    if ( $wds->{options}{no_tables} )
	    {
		$parser->add_output_text( qq{\n<dd><p$attrs>} );
	    }
	    
	    else
	    {
		$parser->add_output_text( qq{<p$attrs>} );
	    }
	}
	
	else
	{
	    $parser->add_output_text( qq{\n<p$attrs>} );
	}
	
	$wds->{listcol} = 2;
    }
    
    elsif ( $element_name eq 'L' )
    {
	my $href;
	
	if ( $attr_hash->{raw} =~ qr{ ^ (?: [^|]* [|] )? (.*) }xs )
	{
	    $href = $1;
	}
	
	else
	{
	    $href = $attr_hash->{to} || "/$attr_hash->{section}";
	}
	
	$wds->{override_text} = $href if $attr_hash->{'content-implicit'};
	
	my $url_gen = $wds->{options}{url_generator};
	$href = $url_gen->($href) if $href && ref $url_gen eq 'CODE';
	
	my $target = '';
	$target = qq{ target="_blank"} if $href =~ qr{ ^ https?: }xsi;
	
	$parser->add_output_text( qq{<a class="pod_link" href="$href"$target>} );
    }
    
    elsif ( $element_name =~ qr{ ^ ( B | I | F | C | S ) $ }xs )
    {
	my $code = $1;
	
	my $tag = 'span';
	# $tag = 'strong' if $element_name eq 'B';
	# $tag = 'em' if $element_name eq 'I';
	# $tag = 'code' if $element_name eq 'C';
	
	if ( $wds->{body}[0] =~ qr{<(?:span|strong|em|code) class="pod_(.)">$}s )
	{
	    my $enclosing = $1;
	    
	    if ( $enclosing eq 'B' && $code eq 'C' )
	    {
		$wds->{body}[0] =~ s{<[^>]+>$}{<span class="pod_term">}s;
		#substr($wds->{body}[0], -3, 1) = "term";
		$wds->{no_span} = 1;
	    }
	    
	    elsif ( $enclosing eq 'C' && $code eq 'B' )
	    {
		$wds->{body}[0] =~ s{<[^>]+>$}{<span class="pod_term2">}s;
		$wds->{no_span} = 1;
	    }
	}
	
	else
	{
	    $parser->add_output_text( qq{<$tag class="pod_$code">} );
	}
    }
    
    elsif ( $element_name =~ qr{ ^ ( X | Z ) $ }xs )
    {
	unshift @{$wds->{body}}, '';
	unshift @{$wds->{target}}, 'xz';
    }
    
    elsif ( $element_name eq 'for' )
    {
	unshift @{$wds->{body}}, '';
	unshift @{$wds->{target}}, $attr_hash->{target};
	
	if ( $element_name eq 'for' && $attr_hash->{target} eq 'wds_pod' )
	{
	    $wds->{for_wds_pod} = 1;
	}
    }
    
    my $a = 1;	# we can stop here when debugging
}


sub _handle_element_end {
    
    my ($parser, $element_name, $attr_hash) = @_;
    
    my $wds = $parser->{wds_fields};
    
    if ( $wds->{options}{debug} )
    {
    	print STDERR "END $element_name";
	
    	foreach my $k (keys %$attr_hash)
    	{
    	    print STDERR " $k=" . $attr_hash->{$k};
    	}
	
    	print STDERR "\n";
    }
    
    if ( $element_name eq 'Para' )
    {
	$parser->add_output_text( qq{</p>} );
    }
    
    elsif ( $element_name eq 'Verbatim' )
    {
	$parser->add_output_text( qq{</pre>} );
    }
    
    elsif ( $element_name eq 'Data' )
    {
	# nothing to do here -- treat contents of Data sections as regular
	# text
    }
    
    elsif ( $element_name =~ qr{ ^ head ( \d ) $ }xsi )
    {
	$parser->add_output_text( qq{</h$1>} );
    }
    
    elsif ( $element_name =~ qr{ ^ over-(bullet|number) $ }xs )
    {
	my $tag = $1 eq 'bullet' ? 'ul' : 'ol';
	$parser->add_output_text( qq{\n\n</$tag>} );
	$wds->{listlevel}--;
    }
    
    elsif ( $element_name =~ qr{ ^ item-(bullet|number) $ }xs )
    {
	$parser->add_output_text( qq{</li>} );
    }
    
    elsif ( $element_name eq 'over-text' )
    {
	if ( $wds->{options}{no_tables} )
	{
	    $parser->add_output_text( qq{</dd>} ) if $wds->{listcol} > 1;
	    $parser->add_output_text( qq{\n\n</dl>} );
	}
	
	else
	{
	    $parser->add_output_text( qq{\n</td></tr>} ) if $wds->{listcol} > 0;
	    $parser->add_output_text( qq{\n\n</table>} );
	}
	
	$wds->{listlevel}--;
	$wds->{listcol} = $wds->{listlevel} > 0 ? 2 : 0;
	shift @{$wds->{table_def}};
    }
    
    elsif ( $element_name eq 'item-text' )
    {
	my $item_text = shift @{$wds->{body}};
	shift @{$wds->{target}};
	
	my $table_def = $wds->{table_def}[0];
	
	if ( ref $table_def->{columns} eq 'ARRAY' )
	{
	    my $last;
	    
	    if ( $item_text =~ qr{ (.*) \s+ [(] \s+ ( [^)]+ ) \s+ [)] }xs )
	    {
		$item_text = $1;
		$last = $2;
	    }
	    
	    my @values = split qr{ \s+ [|/] \s+ }xs, $item_text;
	    push @values, $last if defined $last && $last ne '';
	    
	    if ( $table_def->{expect_subheader} )
	    {
		$table_def->{expect_subheader} = undef;
		
		my $class = $wds->{listlevel} > 1 ? 'pod_th2' : 'pod_th';
		
		$parser->add_output_text( qq{\n\n<tr class="$class">} );
		
		foreach my $i ( 0 .. $table_def->{n_subs} - 1 )
		{
		    my $v = @values ? shift(@values) : '';
		    $parser->add_output_text( qq{<td>$v</td>} );
		}
		
		$parser->add_output_text( qq{</tr>\n\n</td></tr>\n} );
		$wds->{listcol} = 0;
	    }
	    
	    else
	    {
		$parser->add_output_text( qq{\n\n<tr>} );
		
		my @cols = @{$table_def->{columns}};
		pop @cols;
		
		foreach my $col ( @cols )
		{
		    my $v = @values ? shift(@values) : '';
		    my $attrs = '';
		    
		    if ( $wds->{pending_anchor} )
		    {
			$attrs .= qq{ id="$wds->{pending_anchor}"};
			$wds->{pending_anchor} = undef;
		    }
		    
		    if ( $col->{term} )
		    {
			my $class = $wds->{listlevel} > 1 ? 'pod_term2' : 'pod_term';
			$attrs .= qq{ class="$class"};
		    }
		    
		    else
		    {
			my $class = $wds->{listlevel} > 1 ? 'pod_def2' : 'pod_def';
			$attrs .= qq{ class="$class"};
		    }
		    
		    $parser->add_output_text( qq{<td$attrs>$v</td>\n} );
		}
		
		my $class = $wds->{listlevel} > 1 ? 'pod_def2' : 'pod_def';
		$parser->add_output_text( qq{<td class="$class">} );
		$wds->{listcol} = 2;
	    }
	}
	
	else
	{
	    my $termclass = $wds->{listlevel} > 1 ? 'pod_term2' : 'pod_term';
	    my $defclass = $wds->{listlevel} > 1 ? 'pod_def2' : 'pod_def';
	    my $attrs = ''; $attrs .= qq{ class="$termclass"};
	    
	    if ( $wds->{pending_anchor} )
	    {
		$attrs .= qq{ id="$wds->{pending_anchor}"};
		$wds->{pending_anchor} = undef;
	    }
	    
	    if ( $wds->{options}{no_tables} )
	    {
		$parser->add_output_text( qq{\n\n<dt$attrs>$item_text</dt>\n<dd class="$defclass">} );
	    }
	    
	    else
	    {
		$parser->add_output_text( qq{\n\n<tr><td$attrs>$item_text</td>\n<td class="$defclass">} );
	    }
	    
	    $wds->{listcol} = 2;
	}
    }
    
    elsif ( $element_name eq 'L' )
    {
	$parser->add_output_text( qq{</a>} );
	$wds->{override_text} = undef;
    }
    
    elsif ( $element_name =~ qr{ ^ ( B | I | F | C | S ) $ }xs )
    {
	if ( $wds->{no_span} )
	{
	    $wds->{no_span} = undef;
	}
	
	else
	{
	    $parser->add_output_text( qq{</span>} );
	}
    }
    
    elsif ( $element_name =~ qr{ ^ ( X | Z ) $ }xs )
    {
	shift @{$wds->{body}};
	shift @{$wds->{target}};
    }
    
    elsif ( $element_name eq 'for' )
    {
	my $body = shift @{$wds->{body}};
	my $target = shift @{$wds->{target}};
	
	if ( $target eq 'wds_title' )
	{
	    $wds->{title} = $body;
	}
	
	elsif ( $target eq 'wds_anchor' )
	{
	    $wds->{pending_anchor} = $body;
	}
	
	elsif ( $target =~ qr{ ^ wds_table_ (no_)? header $ }xs )
	{
	    $wds->{table_no_header} = 1 if $1;
	    my @columns = split qr{ \s+ [|] \s+ }xs, $body;
	    $wds->{pending_columns} = \@columns;
	    $wds->{header_source_line} = $attr_hash->{start_line};
	}
	
	elsif ( $target =~ qr{ ^ [:]? wds_nav $ }xs )
	{
	    $parser->add_output_text( $body );
	}
	
	elsif ( $target eq 'wds_pod' )
	{
	    if ( lc $body eq 'on' )
	    {
		if ( $wds->{suppress_pod} )
		{
		    my $line = $wds->{suppress_line};
		    push @{$wds->{errors}}, [ $attr_hash->{start_line}, "you already turned 'wds_pod' on at line '$line'" ];
		}
		
		else
		{
		    $wds->{suppress_pod} = 1;
		    $wds->{suppress_line} = $attr_hash->{start_line};
		    $wds->{suppress_output}++;
		}
	    }
	    
	    elsif ( lc $body eq 'off' )
	    {
		$wds->{suppress_pod} = undef;
		$wds->{suppress_line} = undef;
		$wds->{suppress_output}-- if $wds->{suppress_output};
	    }
	    
	    else
	    {
		push @{$wds->{errors}}, [ $attr_hash->{start_line}, "unrecognized value '$body' for target 'wds_pod'" ];
	    }
	    
	    $wds->{for_wds_pod} = undef;
	}
	
	elsif ( $target eq 'html' )
	{
	    my $url_gen = $wds->{options}{url_generator};
	    
	    if ( ref $url_gen eq 'CODE' )
	    {
		$body =~ s{ href=" ([^"]+) " }{ 'href="' . $url_gen->($1) . '"' }xsie;
	    }
	    
	    $parser->add_output_text( $body );
	}
	
	elsif ( $target eq 'comment' || $target eq 'wds_comment' || $target eq 'wds_node' )
	{
	    # ignore content
	}
	
	else
	{
	    push @{$wds->{errors}}, [ $attr_hash->{start_line}, "unrecognized target '$target'" ];
	}
    }
    
    my $a = 1;	# we can stop here when debugging
}


our (%HTML_ENTITY) = ( '<' => '&lt;', '>' => '&gt;' );

sub _handle_text {
    
    my ($parser, $text) = @_;
    
    my $wds = $parser->{wds_fields};
    
    if ( $wds->{options}{debug} )
    {
    	print STDERR "TEXT $text\n";
    }
    
    if ( defined $wds->{override_text} )
    {
	$text = $wds->{override_text};
	$wds->{override_text} = undef;
    }
    
    unless ( $wds->{target}[0] eq 'html' )
    {    
	$text =~ s/([<>])/$HTML_ENTITY{$1}/ge;
    }
    
    $parser->add_output_text( $text );
}


sub add_output_text {
    
    my $wds = $_[0]{wds_fields};
    
    return if $wds->{suppress_output} and @{$wds->{body}} == 1;
    
    $wds->{body}[0] .= $_[1];
}


sub error_output {
    
    my ($parser) = @_;
    
    my $wds = $parser->{wds_fields};
    
    my $error_output = '';
    my @error_lines;
    
    foreach my $error ( @{$wds->{errors}} )
    {
	push @error_lines, qq{<li>Line $error->[0]: $error->[1]</li>\n};
    }
    
    my $errata = $parser->errata_seen;
    
    if ( ref $errata eq 'HASH' && %$errata )
    {
	my @lines = sort { $a <=> $b } keys %$errata;
	
	foreach my $line ( @lines )
	{
	    foreach my $message ( @{$errata->{$line}} )
	    {
		next if $message =~ qr{ alternative \s text .* non-escaped \s [|] }xs;
		
		push @error_lines, qq{<li> line $line: $message</li>\n};
	    }
	}
    }
    
    if ( @error_lines )
    {
	$error_output .= "<h2 class=\"pod_errors\">Errors were found in the source for this page:</h2>\n\n<ul>\n";
	$error_output .= $_ foreach @error_lines;
	$error_output .= "</ul>\n\n";
    }
    
    return $error_output;
}


sub output {
    
    my ($parser) = @_;
    
    my $wds = $parser->{wds_fields};
    
    my $header = $wds->{options}{html_header};
    my $footer = $wds->{options}{html_footer};
    
    my $encoding = $parser->detected_encoding() || 'ISO-8859-1';
    my $css = $wds->{options}{css};
    
    # If no html header was provided, generate a default one.
    
    unless ( $header )
    {
	my $title = $wds->{title} || $wds->{options}{page_title};
	
	$header  = "<html><head>";
	$header .= "<title>$title</title>" if defined $title && $title ne '';
	$header .= "\n";
	$header .= "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=$encoding\" >\n";
	$header .= "<link rel=\"stylesheet\" type=\"text/css\" title=\"pod_stylesheet\" href=\"$css\">\n" if $css;
	$header .= "</head>\n\n";
	
	$header .= "<body class=\"pod\">\n\n";
	$header .= "<!-- generated by Web::DataService::PodParser.pm - do not change this file, instead alter the code that produced it -->\n";
    }
    
    # If errors occurred, list them now.
    
    my $error_output = $parser->error_output;
    
    # If no html footer was provided, generate a default one.
    
    unless ( $footer )
    {
	$footer  = "\n</body>\n";
	$footer .= "</html>\n";
    }
    
    return $header . $parser->{wds_fields}{body}[0] . $error_output . $footer;
}


1;


=head1 NAME

Web::DataService::PodParser - Pod parser module for Web::DataService

=head1 SYNOPSIS

This module provides an engine that can parse Pod and generate HTML, for use
in generating data service documentation pages.  It is used as follows:

    my $parser = Web::DataService::PodParser->new();
    
    $parser->parse_pod($doc_string);
    
    my $doc_html = $parser->generate_html({ attributes... });

=head1 METHODS

This module provides the following methods:

=head2 new

This class method creates a new instance of the parser.

=head2 parse_pod

This method takes a single argument, which must be a string containing Pod
text.  A parse tree is built from this input.

=head2 generate_html

This method uses the parse tree built by C<parse_pod> to create HTML content.
This content is returned as a single string, which can then be sent as the
body of a response message.

This method takes an attribute hash, which can include any of the following
attributes:

=head3 css

The value of this attribute should be the URL of a stylesheet, which will be
included via an HTML <link> tag.  It may be either an absolute or a
site-relative URL.

=head3 tables

If this attribute has a true value, then Pod lists will be rendered as HTML
tables.  Otherwise, they will be rendered as HTML definition lists using the
tags C<dl>, C<dt>, and C<dd>.

=head3 url_generator

The value of this attribute must be a code reference.  This is called whenever
an embedded link is encountered with one of the prefixes C<node:>, C<op:>, or
C<path:>, in order to generate a data service URL corresponding to the
remainder of the link (see
L<Web::DataService::Documentation|Web::DataService::Documentation/Embedded links>).


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

