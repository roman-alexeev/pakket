package Pakket::Repository;
# ABSTRACT: Build in-memory representation of repo

use Moose;
use MooseX::StrictConstructor;

use Path::Tiny;
use Archive::Any;
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

sub latest_version {
    my ( $self, $category, $name ) = @_;

    # TODO: This is where the version comparison goes...
    my @all = grep m{^ \Q$category\E / \Q$name\E =}xms,
              @{ $self->all_object_ids };

    # I don't like this, but okay...
    if ( $all[0] =~ PAKKET_PACKAGE_SPEC() ) {
        return $3;
    }

    die $log->criticalf(
        'Could not analyze %s to find latest version',
        $all[0],
    );
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod
