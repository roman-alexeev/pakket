package Pakket::Versioning::SemVer;
# ABSTRACT: Semantiv Versioning (SemVer) versioning scheme

use Moose;
use MooseX::StrictConstructor;
use SemVer;
use Carp ();
use Pakket::Log qw< $log >;

with qw< Pakket::Role::Versioning >;

# TODO port https://github.com/npm/node-semver

sub sort_candidates {
    my ( $self, $candidates ) = @_;

    return [ sort { SemVer->declare($a) <=> SemVer->declare($b) }
            @{$candidates} ];
}

sub latest_from_range {
    my ( $self, $range ) = @_;
    $log->critical('Range not implemented in SemVer');
    eval { SemVer->new($range); 1; }
    or do {
        my $error = $@ || 'Zombie error';
        $log->criticalf(
            'Error parsing SemVer version %s: %s',
            $range, $error,
        );

        exit 1;
    };

    # return the version
    return $range;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
