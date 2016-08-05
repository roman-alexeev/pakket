package Pakket::Version::Requirements;

use Moose;
use Moose::Util::TypeConstraints;
use Module::Runtime qw< use_module >;

my @valid_schemas = qw<
    perl
    nodejs
>;

has schema_name => (
    is       => 'ro',
    isa      => enum(\@valid_schemas),
    required => 1,
);

has _schema => (
    is       => 'ro',
    does     => 'Pakket::Role::VersionSchema',
    lazy     => 1,
    builder  => '_build_schema',
    handles  => [qw< add_exact add_from_string >],
    init_arg => undef,
);

sub _build_schema {
    my ($self) = @_;

    my $schema_name = ucfirst $self->schema_name;

    return use_module("Pakket::Version::Schema::${schema_name}")->new;
}

sub pick_maximum_satisfying_version {
    my ( $self, $candidates ) = @_;

    my $schema = $self->_schema;

    for my $candidate ( reverse @{ $schema->sort_candidates($candidates) } ) {
        if ( $schema->accepts($candidate) ) {
            return $candidate;
        }
    }

    return;
}

__PACKAGE__->meta->make_immutable;

no Moose;
no Moose::Util::TypeConstraints;

1;
