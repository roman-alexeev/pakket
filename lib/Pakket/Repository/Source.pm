package Pakket::Repository::Source;
# ABSTRACT: A source repository

use Moose;
use MooseX::StrictConstructor;

use Path::Tiny;
use Archive::Any;
use Archive::Tar::Wrapper;

extends qw< Pakket::Repository >;
with    qw< Pakket::Role::HasDirectory >;

sub _build_backend {
    my $self = shift;

    return [
        'File',
        'directory'      => $self->directory,
        'file_extension' => 'spkt',
    ];
}

sub retrieve_package_source {
    my ( $self, $package ) = @_;
    my $file = $self->retrieve_location( $package->full_name );
    my $dir  = Path::Tiny->tempdir( 'CLEANUP' => 1 );
    my $arch = Archive::Any->new( $file->stringify );
    $arch->extract($dir);

    return $dir;
}

sub store_package_source {
    my ( $self, $package, $source_path ) = @_;

    my $arch = Archive::Tar::Wrapper->new();
    $arch->add( $source_path->basename, $source_path->stringify );

    my $file = Path::Tiny->tempfile();

    # Write and compress
    $arch->write( $file->stringify, 1 );

    $self->store_location( $package->full_name, $file );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
