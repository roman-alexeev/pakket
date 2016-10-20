package Pakket::Versioning::SemVer;
# ABSTRACT: Semantiv Versioning (SemVer) versioning scheme

use Moose;
use MooseX::StrictConstructor;
use SemVer;

with qw< Pakket::Role::Versioning >;

# TODO port https://github.com/npm/node-semver

sub accepts {...}

sub add_from_string {...}

sub add_exact {...}

sub sort_candidates {
    my ( $self, $candidates ) = @_;

    return [ sort { SemVer->declare($a) <=> SemVer->declare($b) }
            @{$candidates} ];
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
