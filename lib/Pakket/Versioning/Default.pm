package Pakket::Versioning::Default;
# ABSTRACT: Default versioning scheme

use Moose;
use MooseX::StrictConstructor;
use CPAN::Meta::Requirements;
use version 0.77;
use constant { 'MODULE_NAME' => 'FakeModule' };

with qw< Pakket::Role::Versioning >;

has 'requirements' => (
    'is'      => 'ro',
    'isa'     => 'CPAN::Meta::Requirements',
    'lazy'    => 1,
    'default' => sub { return CPAN::Meta::Requirements->new(); },
);

sub latest_from_range {
    my ( $self, $range ) = @_;

    my $req = $self->requirements;
    $req->add_string_requirement( MODULE_NAME() => $range );

    my @accepted_versions = grep
        $req->accepts_module( MODULE_NAME() => $_ ),
        @{ $self->versions };

    return $self->sort_candidates(@accepted_versions)->[-1];
}

sub sort_candidates {
    my ( $self, $candidates ) = @_;

    return [ sort { version->parse($a) <=> version->parse($b) }
            @{$candidates} ];
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
