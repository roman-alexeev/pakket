package Pakket::Repository::Spec;
# ABSTRACT: A spec repository

use Moose;
use MooseX::StrictConstructor;
use Types::Path::Tiny qw< Path >;
use Carp              qw< croak >;
use JSON::MaybeXS     qw< decode_json >;
use Pakket::Utils     qw< encode_json_canonical >;

extends qw< Pakket::Repository >;
with    qw< Pakket::Role::HasDirectory >;

sub _build_backend {
    my $self = shift;

    return [
        'File',
        'directory'      => $self->directory,
        'file_extension' => 'ini',
    ];
}

sub retrieve_package_spec {
    my ( $self, $package ) = @_;

    my $spec_str = $self->retrieve_content(
        $package->full_name,
    );

    my $config;
    eval {
        $config = decode_json($spec_str);
        1;
    } or do {
        my $err = $@ || 'Unknown error';
        croak("Cannot read spec properly: $err");
    };

    return $config;
}

sub store_package_spec {
    my ( $self, $package ) = @_;

    return $self->store_content(
        $package->full_name,
        encode_json_canonical( $package->spec ),
    );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
