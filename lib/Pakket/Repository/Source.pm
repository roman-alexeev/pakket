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

sub has_parcel {
    my ($self, $category, $name, $version) = @_;

    # FIXME: this is calling all_object_ids every time;
    # could be expensive on a remote backend...
    my @pkgs = grep m{^ \Q$category\E / \Q$name\E = \Q$version\E $}xms,
               @{ $self->all_object_ids() };
    return scalar @pkgs;
}

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
