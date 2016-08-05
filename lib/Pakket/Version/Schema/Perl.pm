package Pakket::Version::Schema::Perl;

use Moose;
use CPAN::Meta::Requirements;

with 'Pakket::Role::VersionSchema';

has requirements => (
    is      => 'ro',
    isa     => 'CPAN::Meta::Requirements',
    lazy    => 1,
    builder => '_build_requirements',
);

sub _build_requirements {
    return CPAN::Meta::Requirements->new;
}

sub accepts {
    my ( $self, $candidate ) = @_;

    return $self->requirements->accepts_module( 'FakeModule', $candidate );
}

sub add_from_string {
    my ( $self, $specifier ) = @_;

    $self->requirements->add_string_requirement( 'FakeModule', $specifier );
}

sub add_exact {
    my ( $self, $version ) = @_;

    $self->requirements->exact_version( 'FakeModule', $version );
}

sub sort_candidates {
    my ( $class, $candidates ) = @_;

    return [ sort { version->parse($a) <=> version->parse($b) }
            @{$candidates} ];
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;
