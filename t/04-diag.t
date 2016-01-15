
use Test::More;
use YAML qw();

plan tests => 20;

$ENV{DANCER_APPDIR} = '.';
$ENV{WDS_QUIET} = 1;

my ($result, $digest);

eval {
    $result = `cd files; $^X bin/dataservice.pl DIAG /data1.0/ 'show=fields&name=pop*&doc=short'`;
};

ok( !$@, 'invocation: diag fields' ) or diag( "    message was: $@" );

unless ( $result )
{
    BAIL_OUT("the data service failed to run.");
}

like( $result, qr{field \s* block \s* definition}xm, 'header line');

like( $result, qr{null \s* : \s* 'pop1900'}xm, 'field line');

like( $result, qr{pop1900 \s* history \s* lib/PopulationData.pm}xm, 'data line' );

like( $result, qr{"The population of the state in 1900"}m, 'doc line' );

eval {
    $result = `cd files; $^X bin/dataservice.pl DIAG /data1.0/ 'show=digest'`;
};

ok( !$@, 'invocation: diag digest' ) or diag( "    message was: $@" );

eval {
    $digest = YAML::Load($result);
};

ok( !$@, 'yaml decode' ) or diag( "    message was: $@" );

is( $digest->{block}{basic}{output_list}[0]{output}, 'name', 'basic block' );

is( $digest->{ds}{data_source}, 'U.S. Bureau of the Census', 'data_source' );

ok( $digest->{ds}{feature}{doc_paths}, 'doc_paths' );

is( $digest->{ds}{format}{json}{name}, 'json', 'format: json' );

ok( $digest->{ds}{vocab}{null}{use_field_names}, 'vocab: null' );

is( $digest->{ds}{special}{linebreak}, 'lb', 'special: linebreak' );

ok( $digest->{node}{'/'}{allow_method}{GET}, 'node "/" allow_method' );

is( $digest->{node}{'/'}{node_list}[0]{path}, 'single', 'node "/" node_list' );

is( $digest->{node}{list}{method}, 'list', 'node "list" method' );

like( $digest->{node}{list}{doc_string}, qr{Returns information about}, 'node "list" doc_string' );

ok( $digest->{node}{list}{allow_format}{csv}, 'node "list" allow_format' );

like( $digest->{ruleset}{list}[0], qr{You can use}, 'ruleset "list" first item' );

ok( $digest->{set}{output_order}{value}{name}, 'set "output_order" value "name"' );
