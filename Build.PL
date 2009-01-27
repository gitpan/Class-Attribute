use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Class::Attribute',
    license             => 'perl',
    dist_author         => 'Bharanee Rathna <deepfryed à gmail>',
    dist_version_from   => 'lib/Class/Attribute.pm',
    build_requires => {
        'Test::More' => 0,
        'Class::Accessor' => 0,
    },
    add_to_cleanup      => [ 'Class-Attribute-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
