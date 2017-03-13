package Pakket::Installer;
# ABSTRACT: Install pakket packages into an installation directory

use Moose;
use MooseX::StrictConstructor;
use Path::Tiny            qw< path  >;
use Types::Path::Tiny     qw< Path  >;
use File::Copy::Recursive qw< dircopy >;
use Time::HiRes           qw< time >;
use Log::Any              qw< $log >;
use JSON::MaybeXS         qw< decode_json >;
use Archive::Any;
use English               qw< -no_match_vars >;

use Pakket::Repository::Parcel;
use Pakket::Requirement;
use Pakket::Package;
use Pakket::Log;
use Pakket::Types     qw< PakketRepositoryBackend >;
use Pakket::Utils     qw< is_writeable encode_json_pretty >;
use Pakket::Constants qw<
    PARCEL_METADATA_FILE
    PARCEL_FILES_DIR
    PAKKET_INFO_FILE
>;

with qw<
    Pakket::Role::HasConfig
    Pakket::Role::HasParcelRepo
    Pakket::Role::RunCommand
>;

has 'pakket_libraries_dir' => (
    'is'      => 'ro',
    'isa'     => Path,
    'coerce'  => 1,
    'builder' => '_build_pakket_libraries_dir',
);

has 'pakket_dir' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

has 'keep_copies' => (
    'is'      => 'ro',
    'isa'     => 'Int',
    'default' => sub {1},
);

sub _build_pakket_libraries_dir {
    my $self = shift;
    return $self->pakket_dir->child('libraries');
}

sub install {
    my ( $self, @packages ) = @_;

    if ( !@packages ) {
        $log->notice('Did not receive any parcels to deliver');
        return;
    }

    my $pakket_libraries_dir = $self->pakket_libraries_dir;

    $pakket_libraries_dir->is_dir
        or $pakket_libraries_dir->mkpath();

    my $work_dir = $pakket_libraries_dir->child( time() );

    if ( $work_dir->exists ) {
        die $log->critical(
            "Internal installation directory exists ($work_dir), exiting",
        );
    }

    $work_dir->mkpath();

    # The only way to make a symlink point somewhere else in an atomic way is
    # to create a new symlink pointing to the target, and then rename it to the
    # existing symlink (that is, overwriting it).
    #
    # This actually works, but there is a caveat: how to generate a name for
    # the new symlink? File::Temp will both create a new file name and open it,
    # returning a handle; not what we need.
    #
    # So, we just create a file name that looks like 'active_P_T.tmp', where P
    # is the pid and T is the current time.
    my $active_link = $pakket_libraries_dir->child('active');
    my $active_temp = $pakket_libraries_dir->child(
        sprintf('active_%s_%s.tmp', $PID, time()),
    );

    # we copy any previous installation
    if ( $active_link->exists ) {
        my $orig_work_dir = eval { my $link = readlink $active_link } or do {
            die $log->critical("$active_link is not a symlink");
        };

        dircopy( $pakket_libraries_dir->child($orig_work_dir), $work_dir );
    }

    my $installer_cache = {};
    foreach my $package (@packages) {
        $self->install_package( $package, $work_dir, { 'cache' => $installer_cache } );
    }

    # We finished installing each one recursively to the work directory
    # Now we need to set the symlink

    if ( $active_temp->exists ) {
        # Huh? why does this temporary pathname exist? Try to delete it...
        $log->debug('Deleting existing temporary active object');
        if ( ! $active_temp->remove ) {
            die $log->error('Could not activate new installation (temporary symlink remove failed)');
        }
    }

    $log->debug('Setting temporary active symlink to new work directory');
    if ( ! symlink $work_dir->basename, $active_temp ) {
        die $log->error('Could not activate new installation (temporary symlink create failed)');
    }
    if ( ! $active_temp->move($active_link) ) {
        die $log->error('Could not atomically activate new installation (symlink rename failed)');
    }

    $log->infof(
        "Finished installing %d packages into $pakket_libraries_dir",
        scalar keys %{$installer_cache},
    );

    log_success( 'Finished installing: ' . join ', ',
        map $_->full_name, @packages );

    # Clean up
    my $keep = $self->keep_copies;

    if ( $keep <= 0 ) {
        $log->warning(
            "You have set your 'keep_copies' to 0 or less. " .
            "Resetting it to '1'.",
        );

        $keep = 1;
    }

    my @dirs = sort { $a->stat->mtime <=> $b->stat->mtime }
               grep +( $_->basename ne 'active' && $_->is_dir ),
               $pakket_libraries_dir->children;

    my $num_dirs = @dirs;
    foreach my $dir (@dirs) {
        $num_dirs-- <= $keep and last;
        $log->debug("Removing old directory: $dir");
        path($dir)->remove_tree( { 'safe' => 0 } );
    }

    return;
}

sub try_to_install_package {
    my ( $self, $package, $dir, $opts ) = @_;

    $log->debugf( 'Trying to install %s', $package->full_name );

    # First we check whether a package exists, because if not
    # we wil throw a silly critical warning about it
    # This can also speed stuff up, but maybe should be put into
    # "has_package" wrapper function... -- SX
    $self->parcel_repo->has_object( $package->id )
        or return;

    eval {
        $self->install_package( $package, $dir, $opts );
        1;
    } or do {
        $log->debugf( 'Could not install %s', $package->full_name );
        return;
    };

    return 1;
}

sub install_package {
    my ( $self, $package, $dir, $opts ) = @_;
    my $installer_cache = $opts->{'cache'};

    # Are we in a regular (non-bootstrap) mode?
    # Are we using a bootstrap version of a package?
    if ( ! $opts->{'skip_prereqs'} && $package->is_bootstrap ) {
        die $log->critical(
            'You are trying to install a bootstrap version of %s.'
          . ' Please rebuild this package from scratch.',
            $package->full_name,
        );
    }

    # Extracted to use more easily in the install cache below
    my $pkg_cat  = $package->category;
    my $pkg_name = $package->name;

    $log->debugf( "About to install %s (into $dir)", $package->full_name );

    if ( defined $installer_cache->{$pkg_cat}{$pkg_name} ) {
        my $ver_rel = $installer_cache->{$pkg_cat}{$pkg_name};
        my ( $version, $release ) = @{$ver_rel};

        # Check version
        if ( $version ne $package->version ) {
            die $log->criticalf(
                "%s=$version already installed. "
              . "Cannot install new version: %s",
              $package->short_name,
              $package->version,
            );
        }

        # Check release
        if ( $release ne $package->release ) {
            die $log->criticalf(
                '%s=%s:%s already installed. '
              . 'Cannot install new version: %s:%s',
                $package->short_name,
                $version, $release,
                $package->release,
            );
        }

        $log->debugf( '%s already installed.', $package->full_name );

        return;
    } else {
        $installer_cache->{$pkg_cat}{$pkg_name} = [
            $package->version, $package->release,
        ];
    }

    if ( !is_writeable($dir) ) {
        die $log->critical(
            "Can't write to your installation directory ($dir)",
        );
    }

    my $parcel_dir
        = $self->parcel_repo->retrieve_package_parcel($package);

    my $full_parcel_dir = $parcel_dir->child( PARCEL_FILES_DIR() );

    # Get the spec and create a new Package object
    # This one will have the dependencies as well
    my $spec_file    = $full_parcel_dir->child( PARCEL_METADATA_FILE() );
    my $spec         = decode_json $spec_file->slurp_utf8;
    my $full_package = Pakket::Package->new_from_spec($spec);

    my $prereqs = $full_package->prereqs;
    foreach my $prereq_category ( keys %{$prereqs} ) {
        my $runtime_prereqs = $prereqs->{$prereq_category}{'runtime'};

        foreach my $prereq_name ( keys %{$runtime_prereqs} ) {
            my $prereq_data = $runtime_prereqs->{$prereq_name};

            # FIXME: This should be removed when we introduce version ranges
            # This forces us to install the latest version we have of
            # something, instead of finding the latest, based on the
            # version range, which "$prereq_version" contains. -- SX
            my $ver_rel = $self->parcel_repo->latest_version_release(
                $prereq_category,
                $prereq_name,
                $prereq_data->{'version'},
            );

            my ( $prereq_version, $prereq_release ) = @{$ver_rel};

            my $prereq = Pakket::Requirement->new(
                'category' => $prereq_category,
                'name'     => $prereq_name,
                'version'  => $prereq_version,
                'release'  => $prereq_release,
            );

            $self->install_package(
                $prereq, $dir,
                { %{$opts}, 'as_prereq' => 1 },
            );
        }
    }

    foreach my $item ( $full_parcel_dir->children ) {
        my $basename = $item->basename;

        $basename eq PARCEL_METADATA_FILE()
            and next;

        my $target_dir = $dir->child($basename);
        dircopy( $item, $target_dir );
    }

    $self->_update_info_file( $parcel_dir, $dir, $full_package, $opts );

    log_success( sprintf 'Delivering parcel %s', $full_package->full_name );

    return;
}

sub _update_info_file {
    my ( $self, $parcel_dir, $dir, $package, $opts ) = @_;

    my $prereqs      = $package->prereqs;
    my $info_file    = $dir->child( PAKKET_INFO_FILE() );
    my $install_data = $info_file->exists
        ? decode_json( $info_file->slurp_utf8 )
        : {};

    my %files;

    # get list of files
    $parcel_dir->visit(
        sub {
            my ( $path, $state ) = @_;

            $path->is_file
                or return;

            my $filename = $path->relative($parcel_dir);
            $files{$filename} = {
                'category' => $package->category,
                'name'     => $package->name,
                'version'  => $package->version,
                'release'  => $package->release,
            };
        },
        { 'recurse' => 1 },
    );

    my ( $cat, $name ) = ( $package->category, $package->name );
    $install_data->{'installed_packages'}{$cat}{$name} = {
        'version'   => $package->version,
        'release'   => $package->release,
        'files'     => [ keys %files ],
        'as_prereq' => $opts->{'as_prereq'} ? 1 : 0,
        'prereqs'   => $package->prereqs,
    };

    foreach my $file ( keys %files ) {
        $install_data->{'installed_files'}{$file} = $files{$file};
    }

    $info_file->spew_utf8( encode_json_pretty($install_data) );
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__
