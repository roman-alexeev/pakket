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
use Pakket::Utils         qw< is_writeable >;
use Pakket::Constants qw<
    PARCEL_METADATA_FILE
    PARCEL_FILES_DIR
    PAKKET_PACKAGE_SPEC
>;

with 'Pakket::Role::RunCommand';

# Sample structure:
# ~/.pakket/
#        bin/
#        etc/
#        repos/
#        libraries/
#                  active ->
#

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

has 'parcel_dir' => (
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

has 'input_file' => (
    'is'        => 'ro',
    'isa'       => Path,
    'coerce'    => 1,
    'predicate' => '_has_input_file',
);

has 'parcel_repo' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Repository::Parcel',
    'lazy'    => 1,
    'builder' => '_build_parcel_repo',
);

# We're starting with a local repo
# # but in the future this will be dictated from a configuration
sub _build_parcel_repo {
    my $self   = shift;

    # Use default for now, but use the directory we want at least
    return Pakket::Repository::Parcel->new(
        'directory' => $self->parcel_dir,
    );
}

sub _build_pakket_libraries_dir {
    my $self = shift;
    return $self->pakket_dir->child('libraries');
}

sub _clean_packages {
    my ( $self, $packages ) = @_;
    my @clean_packages;

    foreach my $package_str ( @{$packages} ) {
        my ( $pkg_cat, $pkg_name, $pkg_version ) =
            $package_str =~ PAKKET_PACKAGE_SPEC();

        if ( !defined $pkg_version ) {
            $log->critical(
                'Currently you must provide a version to install',
            );

            exit 1;
        }

        push @clean_packages, Pakket::Package->new(
            'category' => $pkg_cat,
            'name'     => $pkg_name,
            'version'  => $pkg_version,
        );
    }

    @{ $packages } = @clean_packages;
}

sub install {
    my ( $self, @packages ) = @_;

    $self->_has_input_file and
        push @packages, $self->input_file->lines_utf8( { 'chomp' => 1 } );

    $self->_clean_packages(\@packages);

    if ( !@packages ) {
        $log->notice('Did not receive any parcels to deliver');
        return;
    }

    my $pakket_libraries_dir = $self->pakket_libraries_dir;

    $pakket_libraries_dir->is_dir
        or $pakket_libraries_dir->mkpath();

    my $work_dir = $pakket_libraries_dir->child( time() );

    if ( $work_dir->exists ) {
        $log->critical(
            "Internal installation directory exists ($work_dir), exiting",
        );

        exit 1;
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
            $log->critical("$active_link is not a symlink");
            exit 1;
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
            $log->error('Could not activate new installation (temporary symlink remove failed)');
            exit 1;
        }
    }

    $log->debug('Setting temporary active symlink to new work directory');
    if ( ! symlink $work_dir->basename, $active_temp ) {
        $log->error('Could not activate new installation (temporary symlink create failed)');
        exit 1;
    }
    if ( ! $active_temp->move($active_link) ) {
        $log->error('Could not atomically activate new installation (symlink rename failed)');
        exit 1;
    }

    $log->infof(
        "Finished installing %d packages into $pakket_libraries_dir",
        scalar keys %{$installer_cache},
    );

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
        $log->critical(
            'You are trying to install a bootstrap version of %s.'
          . ' Please rebuild this package from scratch.',
            $package->full_name,
        );

        exit 1;
    }

    # Extracted to use more easily in the install cache below
    my $pkg_cat  = $package->category;
    my $pkg_name = $package->name;

    $log->debugf( "About to install %s (into $dir)", $package->full_name );

    if ( defined $installer_cache->{$pkg_cat}{$pkg_name} ) {
        my $version = $installer_cache->{$pkg_cat}{$pkg_name};

        if ( $version ne $package->version ) {
            $log->criticalf(
                "%s=$version already installed. "
              . "Cannot install new version: %s",
              $package->short_name,
              $package->version,
            );

            exit 1;
        }

        $log->debugf( '%s already installed.', $package->full_name );

        return;
    } else {
        $installer_cache->{$pkg_cat}{$pkg_name} = $package->version;
    }

    if ( !is_writeable($dir) ) {
        $log->critical(
            "Can't write to your installation directory ($dir)",
        );

        exit 1;
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
            my $prereq_data    = $runtime_prereqs->{$prereq_name};
            my $prereq_version = $prereq_data->{'version'};

            my $prereq = Pakket::Requirement->new(
                'category' => $prereq_category,
                'name'     => $prereq_name,
                'version'  => $prereq_version,
            );

            $self->install_package( $prereq, $dir, $opts );
        }
    }

    foreach my $item ( $full_parcel_dir->children ) {
        my $basename = $item->basename;

        $basename eq PARCEL_METADATA_FILE()
            and next;

        my $target_dir = $dir->child($basename);
        dircopy( $item, $target_dir );
    }

    $log->infof( 'Delivered parcel %s', $full_package->full_name );

    return;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__
