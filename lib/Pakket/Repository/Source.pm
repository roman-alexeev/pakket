package Pakket::Repository::Source;
# ABSTRACT: A source repository

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
        'file_extension' => 'spkt',
    ];
}

# FIXME: This is duplicated in the Parcel repo
sub retrieve_package_source {
    my ( $self, $package ) = @_;
    my $file = $self->retrieve_location( $package->full_name );

    if ( !$file ) {
        $log->criticalf(
            'We do not have the source for package %s',
            $package->full_name,
        );

        exit 1;
    }

    my $dir  = Path::Tiny->tempdir( 'CLEANUP' => 1 );
    my $arch = Archive::Any->new( $file->stringify );
    $arch->extract($dir);

    return $dir;
}

sub store_package_source {
    my ( $self, $package, $source_path ) = @_;

    my $arch = Archive::Tar::Wrapper->new();
    $log->debug("Adding $source_path to file");

    $source_path->visit(
        sub {
            my ( $path, $stash ) = @_;

            $path->is_file
                or return;

            $arch->add(
                $path->relative($source_path)->stringify,
                $path->stringify,
            );
        },
        { 'recurse' => 1 },
    );

    my $file = Path::Tiny->tempfile();

    # Write and compress
    $log->debug("Writing archive as $file");
    $arch->write( $file->stringify, 1 );

    $log->debug("Storing $file");
    $self->store_location( $package->full_name, $file );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
