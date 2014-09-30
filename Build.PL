use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Web::DataService',
    license             => 'perl',
    dist_author         => 'Michael McClennen <mmcclenn@cpan.org>',
    dist_version_from   => 'lib/Web/DataService.pm',
    release_status => 'unstable',
    requires => {
	'Dancer' => 0,
	'Moo' => 0,
        'namespace::clean' => 0,
        'HTTP::Validate' => 0.45,
	'Try::Tiny' => 0,
	'JSON' => 0,
	'YAML' => 0,
    },
    recommends => {
	'Template' => 0,
	'Dancer::Plugin::Database' => 0,
    },
    build_requires => {
	'Module::Build' => 0.42,
        'Test::More' => 0,
    },
    #add_to_cleanup      => [ 'Web-DataService-*' ],
    script_files => {
	'script/dsinstallfiles' => 1 
    },
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
