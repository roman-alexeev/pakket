package Pkt::Builder;
# ABSTRACT: Build pkt packages

use Moose;
use Config;
use Path::Tiny                qw< path        >;
use File::Find                qw< find        >;
use File::Copy::Recursive     qw< dircopy     >;
use File::Basename            qw< basename dirname >;
use Algorithm::Diff::Callback qw< diff_hashes >;
use Types::Path::Tiny         qw< Path >;
use TOML::Parser;
use System::Command;

use Pkt::Bundler;

use constant {
    ALL_PACKAGES_KEY => '',
};

has config_dir => (
    is      => 'ro',
    isa     => Path,
    default => sub { Path::Tiny->cwd },
);

has source_dir => (
    is      => 'ro',
    isa     => Path,
    default => sub { Path::Tiny->cwd },
);

has build_dir => (
    is      => 'ro',
    isa     => Path,
    lazy    => 1,
    default => sub { Path::Tiny->tempdir('BUILD-XXXXXX', CLEANUP => 0 ) },
);

has keep_build_dir => (
    is      => 'ro',
    isa     => 'Bool',
    default => sub {0},
);

has log => (
    is      => 'ro',
    isa     => 'Int',
    default => sub {0},
);

has is_built => (
    is      => 'ro',
    isa     => 'HashRef',
    default => sub { +{} },
);

has build_files_manifest => (
    is      => 'ro',
    isa     => 'HashRef',
    default => sub { +{} },
);

has bundler => (
    is      => 'ro',
    isa     => 'Pkt::Bundler',
    lazy    => 1,
    builder => '_build_bundler',
);

has bundler_args => (
    is        => 'ro',
    isa       => 'HashRef',
    default   => sub { +{} },
);

sub _log {
    my ($self, $msg_level, $msg) = @_;

    $self->log >= $msg_level
        and print "$msg\n";

    open my $build_log, '>>', $self->{'build_log_path'}
        or die "Could not open build.log: $!\n";

    print {$build_log} "$msg\n";

    close $build_log
        or die "Could not close build.log: $!\n";
}

sub _log_fatal {
    my ($self, $msg) = @_;
    $self->_log( 0, $msg );
    die "";
}

sub _build_bundler {
    my $self = shift;
    Pkt::Bundler->new( $self->bundler_args );
}

sub build {
    my ( $self, $category, $package ) = @_;

    local $| = 1;

    $self->_reset_build_log;
    $self->_setup_build_dir;
    $self->run_build( $category, $package );
}

sub DEMOLISH {
    my $self      = shift;
    my $build_dir = $self->build_dir;

    if ( ! $self->keep_build_dir ) {
        $self->_log( 1, "Removing build dir $build_dir" );

        # "safe" is false because it might hit files which it does not have
        # proper permissions to delete (example: ZMQ::Constants.3pm)
        # which means it won't be able to remove the directory
        path($build_dir)->remove_tree( { safe => 0 } );
    }
}

sub _reset_build_log {
    my $self = $_[0];
    $self->{'build_log_path'} = path( Path::Tiny->cwd, 'build.log');
    open my $build_log, '>', $self->{'build_log_path'}
        or $self->_log_fatal("Could not create build.log");
    close $build_log;
}

sub _setup_build_dir {
    my $self = shift;

    $self->_log( 1, 'Creating build dir ' . $self->build_dir );
    my $prefix_dir = path( $self->build_dir, 'main' );

    -d $prefix_dir or $prefix_dir->mkpath;
}

sub run_build {
    # FIXME: we're currently not using the third parameter
    my ( $self, $category, $package_name, $prereqs ) = @_;

    my $full_package_name = "$category/$package_name";

    if ( $self->is_built->{$full_package_name} ) {
        $self->_log( 1, "We already built $full_package_name, skipping..." );
        return;
    }

    # FIXME: the config class should have "mandatory" fields, add checks

    # read the configuration
    my $config_file = path(
        $self->config_dir, $category, "$package_name.toml"
    );

    -r $config_file
        or $self->_log_fatal("Could not find package information ($config_file)");

    my $config;
    eval {
        $config = TOML::Parser->new( strict_mode => 1 )->parse_file($config_file);
        1;
    } or do {
        my $err = $@ || 'Unknown error';
        $self->_log_fatal("Cannot read $config_file: $err");
    };

    # double check we have the right package configuration
    my $config_name = $config->{'Package'}{'name'}
        or $self->_log_fatal( "Package config must provide 'name'");

    my $config_category = $config->{'Package'}{'category'}
        or $self->_log_fatal("Package config must provide 'category'");

    $config_name eq $package_name
        or $self->_log_fatal("Mismatch package names ($package_name / $config_name");

    $config_category eq $category
        or $self->_log_fatal( "Mismatch package categories "
             . "($category / $config_category)" );

    # recursively build prereqs
    # starting with system libraries
    # FIXME: we're currently not using the third parameter
    if ( my $system_prereqs = $config->{'Prereqs'}{'system'} ) {
        foreach my $prereq ( keys %{$system_prereqs} ) {
            $self->run_build( 'system', $prereq, $system_prereqs->{$prereq} );
        }
    }

    if ( my $perl_prereqs = $config->{'Prereqs'}{'perl'} ) {
        foreach my $prereq ( keys %{$perl_prereqs} ) {
            $self->run_build( 'perl', $prereq, $perl_prereqs->{$prereq} );
        }
    }

    my $package_src_dir = path(
        $self->source_dir,
        $config->{'Package'}{'directory'},
    );

    $self->_log( 1, 'Copying package files' );
    -d $package_src_dir
        or $self->_log_fatal("Cannot find source dir: $package_src_dir");

    my $top_build_dir = $self->build_dir;

    # FIXME: we shouldn't be generating PKG_CONFIG_PATH every time
    my $pkgconfig_path = path( $top_build_dir, qw<main lib pkgconfig> );
    $self->_log( 1, "Setting PKG_CONFIG_PATH=$pkgconfig_path" );
    local $ENV{'PKG_CONFIG_PATH'} = $pkgconfig_path;

    my $main_build_dir = path( $top_build_dir, 'main' );
    $self->_log( 1, "Setting LD_LIBRARY_PATH=$main_build_dir" );
    local $ENV{'LD_LIBRARY_PATH'} = $main_build_dir;

    # FIXME: Remove in favor of a ::Build::System, ::Build::Perl, etc.
    # FIXME: $package_dst_dir is dictated from the category
    if ( $config_category eq 'system' ) {
        my $package_dst_dir = path(
            $top_build_dir,
            'src',
            $category,
            basename($package_src_dir),
        );

        dircopy( $package_src_dir, $package_dst_dir );

        $self->build_package(
            $package_name,    # zeromq
            $package_dst_dir, # /tmp/BUILD-1/src/system/zeromq-1.4.1
            $main_build_dir,  # /tmp/BUILD-1/main
        );
    } elsif ( $config_category eq 'perl' ) {
        my $package_dst_dir = path(
            $top_build_dir,
            'src',
            $category,
            basename($package_src_dir),
        );

        dircopy( $package_src_dir, $package_dst_dir );

        $self->build_perl_package(
            $package_name,    # ZMQ::Constants
            $package_dst_dir, # /tmp/BUILD-1/src/perl/ZMQ-Constants-...
            $main_build_dir,  # /tmp/BUILD-1/main
        );
    } else {
        $self->_log_fatal("Unrecognized category ($config_category), cannot build this.");
    }

    $self->is_built->{$full_package_name} = 1;

    $self->_log( 1, 'Scanning directory.' );
    # XXX: this is just a bit of a smarter && dumber rsync(1):
    # rsync -qaz BUILD/main/ output_dir/
    # the reason is that we need the diff.
    # if you can make it happen with rsync, remove all of this. :P
    # perhaps rsync(1) should be used to deploy the package files
    # (because then we want *all* content)
    # (only if unpacking it directly into the directory fails)
    my $package_files = $self->retrieve_new_files(
        $category, $package_name, $main_build_dir
    );

    keys %{$package_files}
        or $self->_log_fatal( 'This is odd. Build did not generate new files. '
             . "Cannot package. Stopping." );

    $self->_log( 1, "Bundling $full_package_name" );
    $self->bundler->bundle(
        $main_build_dir,
        {
            category => $category,
            name     => $package_name,
            version  => $config->{'Package'}{'version'},
        },
        $package_files,
    );

    # store per all packages to get the diff
    @{ $self->build_files_manifest }{ keys %{$package_files} } =
        values %{$package_files};
}

sub run_command {
    my ($self, $cmd) = @_;
    $self->_log( 1, $cmd );
    system "$cmd >> $self->{'build_log_path'} 2>&1";
}

sub retrieve_new_files {
    my ( $self, $category, $package_name, $build_dir ) = @_;

    my $nodes     = $self->scan_directory($build_dir);
    my $new_files = $self->_diff_nodes_list(
        $self->build_files_manifest,
        $nodes,
    );

    return $new_files;
}

sub scan_directory {
    my ( $self, $dir ) = @_;
    my $nodes = {};

    File::Find::find( sub {
        # $File::Find::dir  = '/some/path'
        # $_                = 'foo.ext'
        # $File::Find::name = '/some/path/foo.ext'
        my $filename = $File::Find::name;

        # skip directories, we only want files
        -f $filename or return;

        # save the symlink path in order to symlink them
        if ( -l $filename ) {
            path( $nodes->{$filename} = readlink $filename )->is_absolute
                and $self->_log_fatal("Error. Absolute path symlinks aren't supported.");
        } else {
            $nodes->{$filename} = '';
        }
    }, $dir );

    return $nodes;
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
        added   => sub { $nodes_diff{ $_[0] } = $_[1] },
        deleted => sub {
            $self->_log_fatal("Last build deleted previously existing file: $_[0]");
        },
    );

    return \%nodes_diff;
}

sub run_system_command {
    my ($self, $dir, $sys_cmds) = @_;
    $self->_log( 1, join ' ', @{$sys_cmds} );

    my %opt = (
            'cwd' => $dir,
            # 'trace' => $ENV{SYSTEM_COMMAND_TRACE},
        );

    my $cmd = System::Command->new(@{$sys_cmds}, \%opt);
    $cmd->loop_on(
        stdout => sub {
                my $msg = shift;
                $self->_log( 2, $msg );
            },
        stderr => sub {
                my $msg = shift;
                $self->_log( 0, $msg );
            },
    );
}

sub build_package {
    my ( $self, $package, $build_dir, $prefix ) = @_;

    $self->_log( 1, "Building $package" );

    $self->run_system_command($build_dir, ['./configure', "--prefix=$prefix"]);

    $self->run_system_command($build_dir, ['make']);

    $self->run_system_command($build_dir, ['make', 'install']);

    $self->_log( 1, "Done preparing $package" );
}

sub build_perl_package {
    my ( $self, $package, $build_dir, $prefix ) = @_;

    $self->_log( 1, "Building Perl module: $package" );

    local $ENV{'PERL5LIB'} = join ':',
        path( $prefix, qw<share perl>, $Config{'version'} ),
        path( $prefix, qw<lib   perl>, $Config{'version'} );

    my $original_dir = Path::Tiny->cwd;

    $self->run_system_command($build_dir, ["$^X", 'Makefile.PL', "PREFIX=$prefix"]);

    $self->run_system_command($build_dir, ['make']);

    $self->run_system_command($build_dir, ['make', 'install']);

    $self->_log( 1, "Done preparing $package" );
}

__PACKAGE__->meta->make_immutable;

1;

__END__
