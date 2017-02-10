package Pakket::Repository::Parcel;
# ABSTRACT: A parcel repository

use Moose;
use MooseX::StrictConstructor;

use Log::Any qw< $log >;
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
        'file_extension' => 'pkt',
    ];
}

# FIXME: This is duplicated in the Source repo
sub retrieve_package_parcel {
    my ( $self, $package ) = @_;
    my $file = $self->retrieve_location( $package->full_name );

    if ( !$file ) {
        $log->criticalf(
            'We do not have the parcel for package %s',
            $package->full_name,
        );

        exit 1;
    }

    my $dir  = Path::Tiny->tempdir( 'CLEANUP' => 1 );
    my $arch = Archive::Any->new( $file->stringify );
    $arch->extract($dir);

    return $dir;
}

sub store_package_parcel {
    my ( $self, $package, $parcel_path ) = @_;

    my $file;
    if ( $parcel_path->is_file ) {
        # We were given a file, which we assume is a valid tar file.
        $file = $parcel_path;
    }
    elsif ( $parcel_path->is_dir ) {
        # We were given a directory, so we pack it up into a tar file.
        my $arch = Archive::Tar::Wrapper->new();
        $parcel_path->visit(
            sub {
                my ( $path, $stash ) = @_;

                $path->is_file
                    or return;

                $arch->add(
                    $path->relative($parcel_path)->stringify,
                    $path->stringify,
                );
            },
            { 'recurse' => 1 },
        );

        $file = Path::Tiny->tempfile();

        # Write and compress
        $log->debug("Writing archive as $file");
        $arch->write( $file->stringify, 1 );
    }
    else {
        $log->criticalf( "Don't know how to deal with '%s', not file or directory",
                         $parcel_path->stringify );
        exit 1;
    }

    $log->debug("Storing $file");
    $self->store_location( $package->full_name, $file );
}

sub remove_package_parcel {
    my ( $self, $package ) = @_;
    return $self->remove_location( $package->full_name );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
