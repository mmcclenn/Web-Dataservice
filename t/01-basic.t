#!perl -T

use Test::More tests => 1;

use Dancer qw(!pass);
use Web::DataService;
	
my $result = Web::DataService->new({ name => 'a' });

isa_ok( $result, 'Web::DataService', 'web service object' );

