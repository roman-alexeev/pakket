package Pakket::Repository::Spec;
# ABSTRACT: A spec repository

use Moose;
use MooseX::StrictConstructor;
use Types::Path::Tiny qw< Path >;
use Carp              qw< croak >;
use TOML              qw< to_toml >;
use TOML::Parser;

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
        $config = TOML::Parser->new( 'strict_mode' => 1 )
                              ->parse($spec_str);
        1;
    } or do {
        my $err = $@ || 'Unknown error';
        croak("Cannot read config properly: $err");
    };

	return $config;
}

sub store_package_spec {
	my ( $self, $package ) = @_;

    return $self->store_content(
        $package->full_name,
        to_toml( $package->spec ),
    );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
