use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Web::DataService',
    license             => 'perl',
    dist_author         => 'Michael McClennen <mmcclenn@cpan.org>',
    dist_version_from   => 'lib/Web/DataService.pm',
    requires => {
	'Dancer' => 0,
        'HTTP::Validate' => 0.35,
	'Try::Tiny' => 0,
	'JSON' => 0,
    },
    build_requires => {
        'Test::More' => 0,
    },
    add_to_cleanup      => [ 'Web-DataService-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
