package Pakket::Role::Perl::BootstrapModules;
# ABSTRACT: role to provide Perl's list of bootstrap modules (distributions)

use Moose::Role;

# hardcoded list of packages we have to build first
# using core modules to break cyclic dependencies.
# we have to maintain the order in order for packages to build
# this list is an arrayref to maintain order, the elements
# of the list are arrayref tuples of [ module_name, distribution_name ]
has 'perl_bootstrap_modules' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'default' => sub {
        [
            [ 'ExtUtils::MakeMaker'     => 'ExtUtils-MakeMaker' ],
            [ 'Module::Build'           => 'Module-Build' ],
            [ 'Module::Build::WithXSpp' => 'Module-Build-WithXSpp' ],
        ]
    },
);

no Moose::Role;
1;
__END__
