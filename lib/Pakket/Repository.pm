package Pakket::Repository;
# ABSTRACT: Build in-memory representation of repo

use Moose;
use MooseX::StrictConstructor;

use Path::Tiny;
use Archive::Any;
use Log::Any      qw< $log >;
use Pakket::Types qw< PakketRepositoryBackend >;

has 'backend' => (
    'is'      => 'ro',
    'does'    => 'PakketRepositoryBackend',
    'coerce'  => 1,
    'lazy'    => 1,
    'builder' => '_build_backend',
    'handles' => [ qw<
        all_object_ids
        store_content  retrieve_content  remove_content
        store_location retrieve_location remove_location
    > ],
);

sub _build_backend {
    my $self = shift;
    $log->critical(
        'You did not specify a backend '
      . '(using parameter or builder)',
    );

    exit 1;
}

sub BUILD {
    my $self = shift;
    $self->backend();
}

sub retrieve_package_file {
    my ( $self, $type, $package ) = @_;
    my $file = $self->retrieve_location( $package->full_name );

    if ( !$file ) {
        $log->criticalf(
            'We do not have the %s for package %s',
            $type, $package->full_name,
        );

        exit 1;
    }

    my $dir = Path::Tiny->tempdir( 'CLEANUP' => 1 );
    my $arch = Archive::Any->new( $file->stringify );
    $arch->extract($dir);

    return $dir;
}

sub remove_package_file {
    my ( $self, $type, $package ) = @_;
    my $file = $self->retrieve_location( $package->full_name );

    if ( !$file ) {
        $log->criticalf(
            'We do not have the %s for package %s',
            $type, $package->full_name,
        );

        exit 1;
    }

    $log->debug("Removing $type package");
    $self->remove_location( $package->full_name );
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod
