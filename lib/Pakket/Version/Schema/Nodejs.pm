package Pakket::Version::Schema::Nodejs;

use Moose;
use MooseX::StrictConstructor;

with 'Pakket::Role::VersionSchema';

use SemVer;

# TODO port https://github.com/npm/node-semver

sub accepts {
    ...
}

sub add_exact {
    ...
}

sub add_from_string {
    ...
}

sub sort_candidates {
    my ( $self, $candidates ) = @_;

    return [ sort { SemVer->declare($a) <=> SemVer->declare($b) }
            @{$candidates} ];
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;
