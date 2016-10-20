package Pakket::Role::Versioning;
# ABSTRACT: A versioning role, for any scheme

use Moose::Role;

requires qw<
    accepts
    add_exact
    add_from_string
    sort_candidates
>;

sub pick_maximum_satisfying_version {
    my ( $self, $candidates ) = @_;

    foreach my $candidate ( reverse @{ $self->sort_candidates($candidates) } )
    {
        if ( $self->accepts($candidate) ) {
            return $candidate;
        }
    }

    return;
}

no Moose::Role;

1;
