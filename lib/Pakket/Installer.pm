package Pakket::Installer;

# ABSTRACT: Install pakket packages into an installation directory

use JSON::MaybeXS qw<decode_json>;
use Moose;
use Path::Tiny qw< path  >;
use Types::Path::Tiny qw< Path  >;
use File::HomeDir;
use Log::Any qw< $log >;
use Pakket::Log;
use Pakket::Utils qw< is_writeable >;
use Time::HiRes qw<time>;
use namespace::autoclean;

use constant {
    'PARCEL_METADATA_FILE' => 'meta.json',
};

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
has 'pakket_dir' => (
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

    if ( !@parcel_filenames ) {
        $log->notice('Did not receive any parcels to deliver');
        return;
    }

    my $pakket_dir = $self->pakket_dir;
    $pakket_dir->is_dir
        or $pakket_dir->mkpath();

    my $work_dir = $pakket_dir->child( time() );

    if ( $work_dir->exists ) {
        $log->error(
            "Internal installation directory exists ($work_dir), exiting",
        );

        exit 1;
    }

    $work_dir->mkpath();

    my $installed = {};
    foreach my $file (@parcel_filenames) {
        $self->install_parcel( $file, $work_dir, $installed );
    }

    # We finished installing each one recursively to the work directory
    # Now we need to set the symlink
    $log->debug('Setting symlink to new work directory');
    my $active_link = $pakket_dir->child('active');
    $active_link->remove;

    if ( ! symlink $work_dir, $active_link ) {
        $log->error('Could not activate new installation (symlink failed)');
        exit 1;
    }

    $log->info("Finished installing all packages into $pakket_dir");

    return;
}

sub install_parcel {
    my ( $self, $parcel_filename, $dir, $installed ) = @_;

    $log->debug("About to install $parcel_filename");

    if ( $installed->{$parcel_filename}++ ) {
        $log->debug("$parcel_filename already installed");
        return;
    }

    my $parcel_file = path($parcel_filename);

    if ( !$parcel_file->exists ) {
        $log->critical(
            "Bundle file '$parcel_filename' does not exist or can't be read",
        );

        exit 1;
    }

    if ( !is_writeable($dir) ) {
        $log->critical(
            "Can't write to your installation directory ($dir)",
        );

        exit 1;
    }

    # FIXME: $parcel_dirname should come from repo
    my $parcel_basename = $parcel_file->basename;
    my $parcel_dirname  = $parcel_basename =~ s{\.pkt$}{}rxms;
    $parcel_file->copy($dir);

    $log->debug("Unpacking $parcel_basename");

    # TODO: Archive::Any might fit here, but it doesn't support XZ
    # introduce a plugin for it? It could be based on Archive::Tar
    # but I'm not sure Archive::Tar support XZ either -- SX.
    $self->run_command(
        $dir,
        [ qw< tar -xJf >, $parcel_basename ],
    );

    $dir->child($parcel_basename)->remove;

    my $spec_file
        = $dir->child($parcel_dirname)->child( PARCEL_METADATA_FILE() );

    my $config = decode_json $spec_file->slurp_utf8;

    my ( $pkg_name, $pkg_category, $pkg_version )
        = @{ $config->{'Package'} }{qw<name category version>};

    my $runtime_prereqs = $config->{'Prereqs'}{'runtime'};
    foreach my $prereq_name ( keys %{$runtime_prereqs} ) {
        my $prereq_data    = $runtime_prereqs->{$prereq_name};
        my $prereq_version = $prereq_data->{'version'};

        # FIXME We shouldn't be constructing this,
        #       We should just ask the repo for it
        #       It should maintain metadata for this
        #       and API to retrieve it
        my $filename = "$prereq_name-$prereq_version.pkt";
        $self->install_parcel( $filename, $installed );
    }

    $log->info("Delivered parcel $pkg_category/$pkg_name ($pkg_version)");

    return;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__
