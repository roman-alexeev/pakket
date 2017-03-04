package Pakket::Repository;
# ABSTRACT: Build in-memory representation of repo

use Moose;
use MooseX::StrictConstructor;

use Path::Tiny;
use Archive::Any;
use Archive::Tar::Wrapper;
use Log::Any      qw< $log >;
use Pakket::Types qw< PakketRepositoryBackend >;
use Pakket::Constants qw< PAKKET_PACKAGE_SPEC >;

has 'backend' => (
    'is'      => 'ro',
    'does'    => 'PakketRepositoryBackend',
    'coerce'  => 1,
    'lazy'    => 1,
    'builder' => '_build_backend',
    'handles' => [ qw<
        all_object_ids has_object
        store_content  retrieve_content  remove_content
        store_location retrieve_location remove_location
    > ],
);

sub _build_backend {
    my $self = shift;
    die $log->critical(
        'You did not specify a backend '
      . '(using parameter or builder)',
    );
}

sub BUILD {
    my $self = shift;
    $self->backend();
}

sub retrieve_package_file {
    my ( $self, $type, $package ) = @_;
    my $file = $self->retrieve_location( $package->id );

    if ( !$file ) {
        die $log->criticalf(
            'We do not have the %s for package %s',
            $type, $package->full_name,
        );
    }

    my $dir = Path::Tiny->tempdir( 'CLEANUP' => 1 );
    my $arch = Archive::Any->new( $file->stringify );
    $arch->extract($dir);

    return $dir;
}

sub remove_package_file {
    my ( $self, $type, $package ) = @_;
    my $file = $self->retrieve_location( $package->id );

    if ( !$file ) {
        die $log->criticalf(
            'We do not have the %s for package %s',
            $type, $package->full_name,
        );
    }

    $log->debug("Removing $type package");
    $self->remove_location( $package->id );
}

sub latest_version_release {
    my ( $self, $category, $name ) = @_;

    # TODO: This is where the version comparison goes...
    my @all = grep m{^ \Q$category\E / \Q$name\E =}xms,
              @{ $self->all_object_ids };

    # I don't like this, but okay...
    if ( $all[0] =~ PAKKET_PACKAGE_SPEC() ) {
        my ( $version, $release ) = ( $3, $4 );

        defined $version && defined $release
            and return [ $version, $release ];
    }

    die $log->criticalf(
        'Could not analyze %s to find latest version',
        $all[0],
    );
}

sub freeze_location {
    my ( $self, $orig_path ) = @_;

    my $arch = Archive::Tar::Wrapper->new();

    if ( $orig_path->is_file ) {
        $arch->add( $orig_path->basename, $orig_path->stringify, );
    } elsif ( $orig_path->is_dir ) {
        $orig_path->children
            or
            die $log->critical("Cannot freeze empty directory ($orig_path)");

        $orig_path->visit(
            sub {
                my ( $path, $stash ) = @_;

                $path->is_file
                    or return;

                $arch->add( $path->relative($orig_path)->stringify,
                    $path->stringify, );
            },
            { 'recurse' => 1 },
        );
    } else {
        die $log->criticalf( "Unknown location type: %s", $orig_path );
    }

    my $file = Path::Tiny->tempfile();

    # Write and compress
    $log->debug("Writing archive as $file");
    $arch->write( $file->stringify, 1 );

    return $file;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod
