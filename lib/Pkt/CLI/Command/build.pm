package Pkt::CLI::Command::build;

use strict;
use warnings;
use Pkt::CLI -command;

use Config;
use File::Path            qw< make_path remove_tree >;
use Path::Tiny            qw< path     >;
use File::Copy::Recursive qw< dircopy  >;
use File::Basename        qw< basename >;
use TOML::Parser;

# TODO:
# - move all hardcoded values (confs) to constants
# - add make process log (and add it with -v -v)

sub abstract    { 'Build a package' }
sub description { 'Build a package' }

sub opt_spec {
    return (
        [ 'category=s',   'pkt category ("perl", "system", etc.)' ],
        [ 'build-dir=s',  'use an existing build directory'       ],
        [ 'config-dir=s', 'directory holding the configurations'  ],
        [ 'source-dir=s', 'directory holding the sources'         ],
        [ 'verbose|v',    'verbose log'                           ],
    );
}

sub LOG { $_[0]->{'log'} && print STDERR $_[1], "\n" }

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    $self->{'category'} = $opt->{'category'};

    $args->[0]
        or $self->usage_error('Must specify package');

    my ( $cat, $package ) = split '/', $args->[0];

    # did we get a full path spec (category/package)
    if ($package) {
        # if there is a category, it *has* to match
        # the category provided by the full spec
        $self->{'category'} && $self->{'category'} ne $cat
            and $self->usage_error(
                sprintf "You specified two categories: '%s' and '%s'\n",
                        $self->{'category'},
                        $cat
            );

        # use the category we got from the full spec if we don't
        # have one defined already
        # (and if we do, they will match anyway - see check above)
        $self->{'category'} //= $cat;
    }

    # if there is no package, the first item (now in $cat)
    # is the package name
    $self->{'package'} = $package || $cat;

    $self->{'category'}
        or $self->usage_error('You must provide a category');

    if ( $opt->{'build_dir'} ) {
        -d $opt->{'build_dir'}
            or die "You asked to use a build dir that does not exist.\n";
    } else {
        # make sure we got a directory
        my $count;
        while ( my $build_dir = '/tmp/BUILD-' . int rand 999 ) {
            ++$count == 100
                and die "Gave up on creating a new build dir.\n";

            -d $build_dir
                or $self->{'build_dir'} = $build_dir, last;
        }
    }

    $self->{'config_base'} = $opt->{'config_dir'} || '.';
    $self->{'source_base'} = $opt->{'source_dir'} || '.';
    $self->{'log'}         = $opt->{'verbose'};
}

sub execute {
    my $self = shift;

    $self->set_build_dir;

    # method should get category and package to allow clean recursion
    $self->run_build( $self->{'category'}, $self->{'package'} );
}

sub set_build_dir {
    my $self = shift;

    my $prefix_dir = path( $self->{'build_dir'}, 'main' );

    if ( ! -d $prefix_dir ) {
        $self->LOG( 'Creating build dir ' . $self->{'build_dir'} );
        make_path($prefix_dir);
    }
}

sub run_build {
    my ( $self, $category, $package_name, $prereqs ) = @_;

    my $full_package_name = "$category/$package_name";
    $self->{'is_built'}{$full_package_name}
        and return;

    # FIXME: the config class should have "mandatory" fields, add checks

    # read the configuration
    my $config_file = path(
        $self->{'config_base'},
        $category,
        "$package_name.toml"
    );

    my $config;

    -r $config_file
        or die "Could not find package information ($config_file)\n";

    eval {
        $config = TOML::Parser->new( strict_mode => 1 )->parse_file($config_file);
        1;
    } or do {
        my $err = $@ || 'Unknown error';
        $self->usage_error("Cannot read $config_file: $err");
    };

    # double check we have the right package configuration
    my $config_name = $config->{'Package'}{'name'}
        or die "Package config must provide 'name'\n";

    my $config_category = $config->{'Package'}{'category'}
        or die "Package config must provide 'category'\n";

    $config_name eq $package_name
        or die "$package_name configuration claims it is $config_name\n";

    # FIXME: is this already built?
    # once we're done building something, we should be moving it over
    # to the "BUILT" directory (artifact repo) - then we can check if
    # a package is already available there

    # recursively build prereqs
    # starting with system libraries
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
        $self->{'source_base'},
        $config->{'Package'}{'directory'},
    );

    $self->LOG('Copying package files');
    -d $package_src_dir
        or die "Cannot find source dir: $package_src_dir\n";

    my $top_build_dir = $self->{'build_dir'};

    my $pkgconfig_path = path( $top_build_dir, qw<main lib pkgconfig> );
    $self->LOG("Setting PKG_CONFIG_PATH=$pkgconfig_path");
    local $ENV{'PKG_CONFIG_PATH'} = $pkgconfig_path;

    my $main_build_dir = path( $top_build_dir, 'main' );
    $self->LOG("Setting LD_LIBRARY_PATH=$main_build_dir");
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
    }
    elsif ( $config_category eq 'perl' ) {
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
    }
    else {
        die "Unrecognized category ($config_category), cannot build this.\n";
    }

    $self->{'is_built'}{$full_package_name} = 1;

    # FIXME: when to keep, when to clean up
    #        keep for now
    #$self->LOG("Removing build dir $build_dir");
    #remove_tree($build_dir);
}

sub build_package {
    my ( $self, $package, $build_dir, $prefix ) = @_;

    $self->LOG("Building $package");

    my $original_dir = Path::Tiny->cwd;

    chdir $build_dir
        or die "Can't chdir to $build_dir: $!\n";

    $self->LOG("./configure --prefix=$prefix");
    system "./configure --prefix=$prefix >/dev/null 2>&1";

    $self->LOG('make');
    system 'make >/dev/null 2>&1';

    $self->LOG('make install');
    system 'make install >/dev/null 2>&1';

    chdir $original_dir;
    $self->LOG("Done preparing $package");
}

sub build_perl_package {
    my ( $self, $package, $build_dir, $prefix ) = @_;

    $self->LOG("Building Perl module: $package");

    local $ENV{'PERL5LIB'} = join ':',
        path( $prefix, qw<share perl>, $Config{'version'} ),
        path( $prefix, qw<lib   perl>, $Config{'version'} );

    my $original_dir = Path::Tiny->cwd;

    chdir $build_dir
        or die "Can't chdir to $build_dir: $!\n";

    $self->LOG("$^X Makefile.PL PREFIX=$prefix INSTALL_BASE=''");
    system "$^X Makefile.PL PREFIX=$prefix INSTALL_BASE=''";

    $self->LOG('make');
    system 'make';

    $self->LOG('make install');
    system 'make install';

    chdir $original_dir;
    $self->LOG("Done preparing $package");
}

1;

__END__
