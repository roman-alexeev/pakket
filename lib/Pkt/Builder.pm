package Pkt::Builder;
# ABSTRACT: The Pkt builder

use Moose;
use Config;
use File::Path qw< make_path remove_tree >;
use Path::Tiny qw< path >;
use File::Copy::Recursive qw< dircopy  >;
use File::Basename        qw< basename >;
use TOML::Parser;

has config_dir => (
    is      => 'ro',
    isa     => 'Str',
    default => sub { Path::Tiny->cwd->stringify },
);

has source_dir => (
    is      => 'ro',
    isa     => 'Str',
    default => sub { Path::Tiny->cwd->stringify },
);

has build_dir => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub { Path::Tiny->tempdir('BUILD-XXXXXX')->stringify },
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

sub _log {
    my ($self, $msg) = @_;

    $self->log > 1
        and print "$msg\n";

    open my $build_log, '>>', $self->{'build_log_path'}
        or die "Could not open build.log\n";

    print {$build_log} "$msg\n";

    close $build_log;
}

sub _log_fail {
    my ($self, $msg) = @_;
    $self->_log($msg);
    die "";
}

sub build {
    my ( $self, $category, $package ) = @_;

    local $| = 1;

    $self->_reset_build_log;
    $self->_setup_build_dir;
    $self->run_build( $category, $package );
}

sub _reset_build_log {
    my $self = $_[0];
    $self->{'build_log_path'} = path(Cwd::abs_path, 'build.log');
    open(my $build_log, '>', $self->{'build_log_path'}) or $self->_log_fail("Could not create build.log\n");
    close $build_log;
}

sub _setup_build_dir {
    my $self = shift;

    $self->_log( 'Creating build dir ' . $self->build_dir );
    my $prefix_dir = path( $self->build_dir, 'main' );

    -d $prefix_dir
        or make_path($prefix_dir);
}

sub run_build {
    # FIXME: we're currently not using the third parameter
    my ( $self, $category, $package_name, $prereqs ) = @_;

    my $full_package_name = "$category/$package_name";

    if ( $self->is_built->{$full_package_name} ) {
        $self->_log("We already built $full_package_name, skipping...");
        return;
    }

    # FIXME: the config class should have "mandatory" fields, add checks

    # read the configuration
    my $config_file = path(
        $self->config_dir, $category, "$package_name.toml"
    );

    -r $config_file
        or $self->_log_fail("Could not find package information ($config_file)\n");

    my $config;
    eval {
        $config = TOML::Parser->new( strict_mode => 1 )->parse_file($config_file);
        1;
    } or do {
        my $err = $@ || 'Unknown error';
        $self->_log_fail("Cannot read $config_file: $err\n");
    };

    # double check we have the right package configuration
    my $config_name = $config->{'Package'}{'name'}
        or $self->_log_fail("Package config must provide 'name'\n");

    my $config_category = $config->{'Package'}{'category'}
        or $self->_log_fail("Package config must provide 'category'\n");

    $config_name eq $package_name
        or $self->_log_fail("$package_name configuration claims it is $config_name\n");

    # FIXME: is this already built?
    # once we're done building something, we should be moving it over
    # to the "BUILT" directory (artifact repo) - then we can check if
    # a package is already available there

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

    $self->_log('Copying package files');
    -d $package_src_dir
        or $self->_log_fail("Cannot find source dir: $package_src_dir\n");

    my $top_build_dir = $self->build_dir;

    # FIXME: we shouldn't be generating PKG_CONFIG_PATH every time
    my $pkgconfig_path = path( $top_build_dir, qw<main lib pkgconfig> );
    $self->_log("Setting PKG_CONFIG_PATH=$pkgconfig_path");
    local $ENV{'PKG_CONFIG_PATH'} = $pkgconfig_path;

    my $main_build_dir = path( $top_build_dir, 'main' );
    $self->_log("Setting LD_LIBRARY_PATH=$main_build_dir");
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
        $self->_log_fail("Unrecognized category ($config_category), cannot build this.\n");
    }

    $self->is_built->{$full_package_name} = 1;

    # FIXME: when to keep, when to clean up
    #        keep for now
    #$self->_log("Removing build dir $build_dir");
    #remove_tree($build_dir);
}

sub run_command {
    my ($self, $cmd) = @_;
    system "$cmd >> $self->{'build_log_path'} 2>&1";
}

sub build_package {
    my ( $self, $package, $build_dir, $prefix ) = @_;

    $self->_log("Building $package");

    my $original_dir = Path::Tiny->cwd;

    chdir $build_dir
        or $self->_log_fail("Can't chdir to $build_dir: $!\n");

    $self->_log("./configure --prefix=$prefix");
    $self->run_command("./configure --prefix=$prefix");

    $self->_log('make');
    $self->run_command('make');

    $self->_log('make install');
    $self->run_command('make install');

    chdir $original_dir;
    $self->_log("Done preparing $package");
}

sub build_perl_package {
    my ( $self, $package, $build_dir, $prefix ) = @_;

    $self->_log("Building Perl module: $package");

    local $ENV{'PERL5LIB'} = join ':',
        path( $prefix, qw<share perl>, $Config{'version'} ),
        path( $prefix, qw<lib   perl>, $Config{'version'} );

    my $original_dir = Path::Tiny->cwd;

    chdir $build_dir
        or $self->_log_fail("Can't chdir to $build_dir: $!\n");

    $self->_log("$^X Makefile.PL PREFIX=$prefix INSTALL_BASE=''");
    $self->run_command("$^X Makefile.PL PREFIX=$prefix INSTALL_BASE=''");

    $self->_log('make');
    $self->run_command('make');

    $self->_log('make install');
    $self->run_command('make install');

    chdir $original_dir;
    $self->_log("Done preparing $package");
}

__PACKAGE__->meta->make_immutable;

1;
