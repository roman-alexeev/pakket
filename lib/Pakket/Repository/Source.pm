package Pakket::Repository::Source;
# ABSTRACT: A source repository

use Moose;
use MooseX::StrictConstructor;

use Log::Any qw< $log >;
use Path::Tiny;
use Archive::Tar::Wrapper;

extends qw< Pakket::Repository >;

sub retrieve_package_source {
    my ( $self, $package ) = @_;
    return $self->retrieve_package_file( 'source', $package );
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
    $self->store_location( $package->id, $file );
}

sub remove_package_source {
    my ( $self, $package ) = @_;
    return $self->remove_package_file( 'source', $package );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
