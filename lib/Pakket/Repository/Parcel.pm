package Pakket::Repository::Parcel;
# ABSTRACT: A parcel repository

use Moose;
use MooseX::StrictConstructor;
use Path::Tiny;

extends qw< Pakket::Repository >;
with    qw< Pakket::Role::HasDirectory >;

sub _build_backend {
    my $self = shift;

    return [
        'File',
        'directory'      => $self->directory,
        'file_extension' => 'pkt',
    ];
}

sub retrieve_package_parcel {
    my ( $self, $package ) = @_;
    return $self->retrieve_location( $package->full_name );
}

sub store_package_parcel {
    my ( $self, $package, $parcel_file ) = @_;

    return $self->store_location(
        $package->full_name,
        $parcel_file,
    );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
