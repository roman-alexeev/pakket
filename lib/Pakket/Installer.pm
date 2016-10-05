package Pakket::Installer;

# ABSTRACT: Install pakket packages into an installation directory

use Moose;
use Path::Tiny qw< path  >;
use Types::Path::Tiny qw< Path  >;
use File::HomeDir;
use Log::Any qw< $log >;
use Pakket::Log;
use Pakket::Utils qw< is_writeable >;
use namespace::autoclean;

with 'Pakket::Role::RunCommand';

# TODO:
# * Recursively install
# * Support .pakket.local (or .pakket.config local file configuration)
# * Support multiple libraries
# * Support active library

# Sample structure:
# ~/.pakket/
#        bin/
#        etc/
#        repos/
#        libraries/
#                  active ->
#

# TODO: Derive from a config
# --local should do it in $HOME
has 'library_dir' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

# TODO:
# this should be implemented using a fetcher class
# because it might be from HTTP/FTP/Git/Custom/etc.
sub fetch_package;

sub install {
    my ( $self, @parcel_filenames ) = @_;

    foreach my $file (@parcel_filenames) {
        $self->install_parcel($file);
    }

    return;
}

sub install_parcel {
    my ( $self, $parcel_filename ) = @_;

    my $parcel_file = path($parcel_filename);

    if ( ! $parcel_file->exists ) {
        $log->critical(
            "Bundle file '$parcel_filename' does not exist or can't be read",
        );

        exit 1;
    }

    my $library_dir = $self->library_dir;

    $library_dir->is_dir
        or $library_dir->mkpath();

    if ( !is_writeable($library_dir) ) {
        $log->critical(
            "Can't write to your installation directory ($library_dir)",
        );

        exit 1;
    }

    my $parcel_basename = $parcel_file->basename;
    $parcel_file->copy($library_dir);

    # TODO: Archive::Any might fit here, but it doesn't support XZ
    # introduce a plugin for it? It could be based on Archive::Tar
    # but I'm not sure Archive::Tar support XZ either -- SX.
    $self->run_command(
        $library_dir,
        [ qw< tar -xJf >, $parcel_basename ],
    );

    $library_dir->child($parcel_basename)->remove;

    print "Delivered parcel $parcel_basename to $library_dir\n";

    return;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__
