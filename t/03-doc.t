#!perl -T

use Test::More;

eval "use Template";

if ( $@ )
{
    diag "";
    diag "********************************************************************************";
    diag "***                                                                          ***";
    diag "*** Template Toolkit not installed: no documentation pages will be available ***";
    diag "***                                                                          ***";
    diag "********************************************************************************";
    plan skip_all => "Install Template Toolkit in order to run this test.";
    exit;
}

plan tests => 17;

# Untaint $^X and the path.  Is there a better way to do this?  I am assuming that
# since this is a test script we do not have to worry about these being compromised.

$^X =~ /(.*)/;
my $perl = $1;

$ENV{PATH} =~ /(.*)/;
$ENV{PATH} = $1;

$ENV{DANCER_APPDIR} = '.';
$ENV{WDS_QUIET} = 1;

my ($result);

eval {
    $result = `cd files; $perl bin/dataservice.pl GET /data1.0/`;
};

ok( !$@, 'invocation: main html' ) or diag( "    message was: $@" );

like( $result, qr{^HTTP/1.0 200 OK}m, 'http header' );

like( $result, qr{^Content-Type: text/html; charset=utf-8}m, 'content type html' );

like( $result, qr{^<html><head><title>Example Data Service: Main Documentation</title>}m, 'main title' );

like( $result, qr{^<h2 class="pod_heading"><a name="Operations">Operations</a></h2>}m, 'main h2' );

like( $result, qr{^<td class="pod_def"><p class="pod_para">The JSON format is intended primarily to support client applications.</p>}m, 
      'main json format' );

eval {
    $result = `cd files; $perl bin/dataservice.pl GET /data1.0/index.pod`;
};

ok( !$@, 'invocation: main pod' ) or diag( "    message was: $@" );

like( $result, qr{^Content-Type: text/plain; charset=utf-8}m, 'content type pod' );

like( $result, qr{^=head1 Example Data Service: Main Documentation}m, 'pod title' );

like( $result, qr{^=for wds_table_header Format\* \| Suffix \| Documentation \| Description}m, 'pod table descriptor' );

like( $result, qr{^=item L<Single state\|node:single>}m, 'pod node link' );

eval {
    $result = `cd files; $perl bin/dataservice.pl GET /data1.0/single_doc.pod`;
};

ok( !$@, 'invocation: single_doc html' ) or diag( "    message was: $@" );

like( $result, qr{^=for wds_table_header Field name* | Block | Description}m, 'single_doc response table header' );

like( $result, qr{^=item name \( basic \)}m, 'single_doc basic item' );

like( $result, qr{^The name of the state}m, 'single_doc basic item body' );

like( $result, qr{^=item pop1900 \( hist \)}m, 'single_doc optional item' );

like( $result, qr{^L<Plain text formats\|node:formats/text>}m, 'single_doc format' );
