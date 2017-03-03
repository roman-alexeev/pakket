package Pakket::Builder;
# ABSTRACT: Build pakket packages

use Moose;
use MooseX::StrictConstructor;
use List::Util                qw< first       >;
use Path::Tiny                qw< path        >;
use File::Copy::Recursive     qw< dircopy     >;
use Algorithm::Diff::Callback qw< diff_hashes >;
use Types::Path::Tiny         qw< Path >;
use Log::Any                  qw< $log >;
use version 0.77;

use Pakket::Log;
use Pakket::Package;
use Pakket::Bundler;
use Pakket::Installer;
use Pakket::Requirement;
use Pakket::Builder::NodeJS;
use Pakket::Builder::Perl;
use Pakket::Builder::Native;

use Pakket::Utils qw< generate_env_vars >;

use constant {
    'BUILD_DIR_TEMPLATE' => 'BUILD-XXXXXX',
};

with qw<
    Pakket::Role::HasConfig
    Pakket::Role::HasSpecRepo
    Pakket::Role::HasSourceRepo
    Pakket::Role::HasParcelRepo
    Pakket::Role::Perl::BootstrapModules
    Pakket::Role::RunCommand
>;

has 'build_dir' => (
    'is'      => 'ro',
    'isa'     => Path,
    'coerce'  => 1,
    'lazy'    => 1,
    'default' => sub {
        return Path::Tiny->tempdir(
            BUILD_DIR_TEMPLATE(),
            'CLEANUP' => 0,
        );
    },
);

has 'keep_build_dir' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => sub {0},
);

has 'is_built' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { +{} },
);

has 'build_files_manifest' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { +{} },
);

has 'builders' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub {
        return {
            'nodejs' => Pakket::Builder::NodeJS->new(),
            'perl'   => Pakket::Builder::Perl->new(),
            'native' => Pakket::Builder::Native->new(),
        };
    },
);

has 'bundler' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Bundler',
    'lazy'    => 1,
    'builder' => '_build_bundler',
);

has 'installer' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Installer',
    'lazy'    => 1,
    'default' => sub {
        my $self = shift;

        return Pakket::Installer->new(
            'pakket_dir'  => $self->build_dir,
            'parcel_repo' => $self->parcel_repo,
        );
    },
);

has 'installer_cache' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { +{} },
);

has 'bootstrapping' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 1,
);

sub _build_bundler {
    my $self = shift;

    return Pakket::Bundler->new(
        'parcel_repo' => $self->parcel_repo,
    );
}

sub build {
    my ( $self, $requirement ) = @_;

    $self->_setup_build_dir;
    $self->bootstrapping
        and $self->bootstrap_build( $requirement->category );
    $self->run_build($requirement);
}

sub DEMOLISH {
    my $self      = shift;
    my $build_dir = $self->build_dir;

    if ( !$self->keep_build_dir ) {
        $log->info("Removing build dir $build_dir");

        # "safe" is false because it might hit files which it does not have
        # proper permissions to delete (example: ZMQ::Constants.3pm)
        # which means it won't be able to remove the directory
        $build_dir->remove_tree( { 'safe' => 0 } );
    }

    return;
}

sub _setup_build_dir {
    my $self = shift;

    $log->debugf( 'Creating build dir %s', $self->build_dir->stringify );
    my $prefix_dir = $self->build_dir->child('main');

    $prefix_dir->is_dir or $prefix_dir->mkpath;

    return;
}

sub bootstrap_build {
    my ( $self, $category ) = @_;

    my @dists =
        $category eq 'perl' ? @{ $self->perl_bootstrap_modules } :
        # add more categories here
        ();

    @dists or return;

    ## no critic qw(BuiltinFunctions::ProhibitComplexMappings Lax::ProhibitComplexMappings::LinesNotStatements)
    my %dist_reqs = map {;
        my $name    = $_;
        my $ver_rel = $self->spec_repo->latest_version_release(
            $category, $name,
        );
        my ( $version, $release ) = @{$ver_rel};

        $name => Pakket::Requirement->new(
            'name'     => $name,
            'category' => $category,
            'version'  => $version,
            'release'  => $release,
        );
    } @dists;

    foreach my $dist_name ( keys %dist_reqs ) {
        my $dist_req = $dist_reqs{$dist_name};

        $self->parcel_repo->has_object($dist_req)
            or next;

        $log->noticef(
            'Skipping: parcel %s already exists',
            $dist_req->full_name,
        );

        delete $dist_reqs{$dist_name};
    }

    # Pass I: bootstrap toolchain - build w/o dependencies
    for my $dist_name ( keys %dist_reqs ) {
        my $dist_req = $dist_reqs{$dist_name};

        $log->noticef( 'Bootstrapping: phase I: %s (%s)',
                       $dist_req->full_name, 'no-deps' );

        $self->run_build(
            $dist_req,
            { 'bootstrapping_1_skip_prereqs' => 1 },
        );
    }

    # Pass II: bootstrap toolchain - build dependencies only
    for my $dist_name ( keys %dist_reqs ) {
        my $dist_req = $dist_reqs{$dist_name};

        $log->noticef( 'Bootstrapping: phase II: %s (%s)',
                       $dist_req->full_name, 'deps-only' );

        $self->run_build(
            $dist_req,
            { 'bootstrapping_2_deps_only' => 1 },
        );
    }

    # Pass III: bootstrap toolchain - rebuild w/ dependencies
    # XXX: Whoa!
    my $bootstrap_builder = ref($self)->new(
        'parcel_repo'    => $self->parcel_repo,
        'spec_repo'      => $self->spec_repo,
        'source_repo'    => $self->source_repo,
        'keep_build_dir' => $self->keep_build_dir,
        'builders'       => $self->builders,
        'installer'      => $self->installer,
        'bootstrapping'  => 0,
    );

    for my $dist_name ( keys %dist_reqs ) {
        my $dist_req = $dist_reqs{$dist_name};

        # remove the temp (no-deps) parcel
        $log->noticef( 'Removing %s (no-deps parcel)',
                       $dist_req->full_name );

        $self->parcel_repo->remove_package_parcel($dist_req);

        # build again with dependencies

        $log->noticef( 'Bootstrapping: phase III: %s (%s)',
                       $dist_req->full_name, 'full deps' );

        $bootstrap_builder->build($dist_req);
    }

    $log->notice('Finished Bootstrapping!');
}

sub run_build {
    my ( $self, $prereq, $params ) = @_;
    $params //= {};
    my $level             = $params->{'level'}                        || 0;
    my $skip_prereqs      = $params->{'bootstrapping_1_skip_prereqs'} || 0;
    my $bootstrap_prereqs = $params->{'bootstrapping_2_deps_only'}    || 0;
    my $short_name        = $prereq->short_name;

    # FIXME: GH #29
    if ( $prereq->category eq 'perl' ) {
        # XXX: perl_mlb is a MetaCPAN bug
        first { $prereq->name eq $_ } qw<perl perl_mlb>
            and return;
    }

    if ( ! $bootstrap_prereqs and defined $self->is_built->{$short_name} ) {
        my $ver_rel = $self->is_built->{$short_name};
        my ( $built_version, $built_release ) = @{$ver_rel};

        # Check the versions mismatch
        if ( $built_version ne $prereq->version ) {
            die $log->criticalf(
                'Asked to build %s when %s=%s already built',
                $prereq->full_name, $short_name, $built_version,
            );
        }

        # Check the releases mismatch
        if ( $built_release ne $prereq->release ) {
            die $log->criticalf(
                'Asked to build %s when %s=%s:%s already built',
                $prereq->full_name, $short_name, $built_version, $built_release,
            );
        }

        $log->debug(
            "We already built or building $short_name, skipping...",
        );

        return;
    } else {
        $self->is_built->{$short_name} = [
            $prereq->version,
            $prereq->release,
        ];
    }

    $log->noticef( '%sWorking on %s', '|...' x $level, $prereq->full_name );

    # Create a Package instance from the spec
    # using the information we have on it
    my $package_spec = $self->spec_repo->retrieve_package_spec($prereq);
    my $package      = Pakket::Package->new_from_spec( +{
        %{$package_spec},

        # We are dealing with a version which should not be installed
        # outside of a bootstrap phase, so we're "marking" this package
        'is_bootstrap' => !!$skip_prereqs,
    } );

    my $top_build_dir  = $self->build_dir;
    my $main_build_dir = $top_build_dir->child('main');

    my $installer = $self->installer;

    if ( !$skip_prereqs && !$bootstrap_prereqs ) {
        my $installer_cache = $self->installer_cache;
        my $bootstrap_cache = {
            %{ $self->installer_cache },

            # Phase 3 needs to avoid trying to install
            # the bare minimum toolchain (Phase 1)
            $prereq->category => { $package->name => $package->version },
        };

        my $successfully_installed = $installer->try_to_install_package(
            $package,
            $main_build_dir,
            {
                'cache'        => ( $self->bootstrapping ? $installer_cache : $bootstrap_cache ),
                'skip_prereqs' => $skip_prereqs,
            },
        );

        if ($successfully_installed) {

            # snapshot_build_dir
            $self->snapshot_build_dir( $package, $main_build_dir->absolute, 0 );

            $log->noticef(
                '%sInstalled %s',
                '|...' x $level,
                $prereq->full_name,
            );

            # sync build cache with our install cache
            # so we do not accidentally build things
            # that were installed in some recursive iteration
            foreach my $category ( sort keys %{$installer_cache} ) {
                foreach my $package_name (
                    keys %{ $installer_cache->{$category} } )
                {
                    $self->is_built->{"$category/$package_name"}
                        = $installer_cache->{$category}{$package_name};
                }
            }

            return;
        }
    }

    # GH #74
    my @supported_phases = qw< configure runtime >;

    # recursively build prereqs
    if ( $bootstrap_prereqs or ! $skip_prereqs ) {
        foreach my $category ( keys %{ $self->builders } ) {
            $self->_recursive_build_phase( $package, $category, 'configure', $level+1 );
            $self->_recursive_build_phase( $package, $category, 'runtime', $level+1 );
        }
    }

    $bootstrap_prereqs and return; # done building prereqs
    my $package_src_dir
        = $self->source_repo->retrieve_package_source($package);

    $log->info('Copying package files');

    # FIXME: we shouldn't be generating PKG_CONFIG_PATH every time
    #        Instead, set this as default opt and send it to the build
    #        subroutines as "default opts" to add their own stuff to
    #        and add LD_LIBRARY_PATH and PATH to this as well
    my $pkgconfig_path = $top_build_dir->child( qw<main lib pkgconfig> );
    $log->info("Setting PKG_CONFIG_PATH=$pkgconfig_path");
    local $ENV{'PKG_CONFIG_PATH'} = $pkgconfig_path;

    # FIXME: This shouldn't just be configure flags
    # we should allow the builder to have access to a general
    # metadata chunk which *might* include configure flags
    my $configure_flags = $self->get_configure_flags(
        $package->build_opts->{'configure_flags'},
        { %ENV, generate_env_vars( $top_build_dir, $main_build_dir ) },
    );

    if ( my $builder = $self->builders->{ $package->category } ) {
        my $package_dst_dir = $top_build_dir->child(
            'src',
            $package->category,
            $package_src_dir->basename,
        );


        # FIXME: This feels like such a hack...
        # Basically the tmp dir will still have the dist dir inside it
        # So this goes in and makes sure it's only one directory inside
        my @inner_dirs = $package_src_dir->children;
        if ( @inner_dirs != 1 ) {
            die $log->critical('We only expect one directory in a source tree');
        }

        my $real_package_src_dir = $inner_dirs[0];
        dircopy( $real_package_src_dir, $package_dst_dir );

        $builder->build_package(
            $package->name,
            $package_dst_dir,
            $main_build_dir,
            $configure_flags,
        );
    } else {
        die $log->criticalf(
            'I do not have a builder for category %s.',
            $package->category,
        );
    }

    my $package_files = $self->snapshot_build_dir(
        $package, $main_build_dir,
    );

    $log->infof( 'Bundling %s', $package->full_name );
    $self->bundler->bundle(
        $main_build_dir->absolute,
        $package,
        $package_files,
    );

    $log->noticef(
        '%sFinished on %s', '|...' x $level, $prereq->full_name,
    );

    return;
}

sub _recursive_build_phase {
    my ( $self, $package, $category, $phase, $level ) = @_;
    my @prereqs = keys %{ $package->prereqs->{$category}{$phase} };

    foreach my $prereq_name (@prereqs) {
        my $ver_rel = $self->spec_repo->latest_version_release(
            $category, $prereq_name,
        );

        my ( $version, $release ) = @{$ver_rel};

        my $req = Pakket::Requirement->new(
            'category' => $category,
            'name'     => $prereq_name,
            'version'  => $version,
            'release'  => $release,
        );

        $self->run_build( $req, { 'level' => $level } );
    }
}

sub snapshot_build_dir {
    my ( $self, $package, $main_build_dir, $error_out ) = @_;
    $error_out //= 1;

    $log->debug('Scanning directory.');

    # XXX: this is just a bit of a smarter && dumber rsync(1):
    # rsync -qaz BUILD/main/ output_dir/
    # the reason is that we need the diff.
    # if you can make it happen with rsync, remove all of this. :P
    # perhaps rsync(1) should be used to deploy the package files
    # (because then we want *all* content)
    # (only if unpacking it directly into the directory fails)
    my $package_files = $self->retrieve_new_files($main_build_dir);

    if ($error_out) {
        keys %{$package_files}
            or die $log->criticalf(
                'This is odd. %s build did not generate new files. '
                    . 'Cannot package.',
                $package->full_name,
            );
    }

    # store per all packages to get the diff
    @{ $self->build_files_manifest }{ keys( %{$package_files} ) }
        = values %{$package_files};

    return $package_files;
}

sub retrieve_new_files {
    my ( $self, $build_dir ) = @_;

    my $nodes = $self->_scan_directory($build_dir);
    my $new_files
        = $self->_diff_nodes_list( $self->build_files_manifest, $nodes, );

    return $new_files;
}

sub _scan_directory {
    my ( $self, $dir ) = @_;

    my $visitor = sub {
        my ( $node, $state ) = @_;

        return if $node->is_dir;

        # save the symlink path in order to symlink them
        if ( -l $node ) {
            path( $state->{ $node->absolute } = readlink $node )->is_absolute
                and die $log->critical(
                    "Error. Absolute path symlinks aren't supported."
                );
        } else {
            $state->{ $node->absolute } = '';
        }
    };

    return $dir->visit(
        $visitor,
        { 'recurse' => 1, 'follow_symlinks' => 0 },
    );
}

# There is a possible micro optimization gain here
# if we diff and copy in the same loop
# instead of two steps
sub _diff_nodes_list {
    my ( $self, $old_nodes, $new_nodes ) = @_;

    my %nodes_diff;
    diff_hashes(
        $old_nodes,
        $new_nodes,
        'added'   => sub { $nodes_diff{ $_[0] } = $_[1] },
        'deleted' => sub {
            die $log->critical(
                "Last build deleted previously existing file: $_[0]");
        },
    );

    return \%nodes_diff;
}

sub get_configure_flags {
    my ( $self, $config, $expand_env ) = @_;

    $config or return [];

    my @flags = map +( join '=', $_, $config->{$_} ), keys %{$config};

    $self->_expand_flags_inplace( \@flags, $expand_env );

    return \@flags;
}

sub _expand_flags_inplace {
    my ( $self, $flags, $env ) = @_;

    for my $flag ( @{$flags} ) {
        for my $key ( keys %{$env} ) {
            my $placeholder = '%' . uc($key) . '%';
            $flag =~ s/$placeholder/$env->{$key}/gsm;
        }
    }

    return;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__
