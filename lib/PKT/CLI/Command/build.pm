package PKT::CLI::Command::build;

use PKT::CLI -command;

use strict;
use warnings;
use Config;
use File::Path            qw< make_path remove_tree >;
use Path::Tiny            qw< path     >;
use File::Copy::Recursive qw< dircopy  >;
use File::Basename        qw< basename >;
use TOML::Parser;

# TODO:
# - replace "program" and "program name" with "package" and "package name"
# - move all hardcoded values (confs) to constants
# - add make process log (and add it with -v -v)

sub abstract    { "build" }
sub description { "description" }

sub opt_spec {
    return (
        [ "category=s", "build type (perl,system,etc.)" ],
        [ "config=s", "config directory" ],
        [ "b|build-dir=s", "build directory" ],
        [ "s|source=s", "source directory" ],
        [ "f|for=s",    "build for specific Perl version (current not supported)" ],
        [ "v|verbose", "verbose log" ],
    );
}

sub LOG { $_[0]->{log} && print STDERR $_[1], "\n" }

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    $self->{category} = $opt->{category};

    $args->[0] or $self->usage_error("must specify action");
    my ( $cat, $program ) = split '/' => $args->[0];
    if ( $program ) {
        $self->usage_error("you specified two categories: '" . $self->{category} . "' and '$cat'\n")
            if $self->{category} and $self->{category} ne $cat;
        $self->{category} //= $cat;
    }

    $self->{program} = $program || $cat;

    $self->{build_dir} = $opt->{'build-dir'} || $opt->{b}
        || '/tmp/BUILD-' . int rand 9999;

    $self->{config_base} = $opt->{config}  || '.';
    $self->{source_base} = $opt->{source}  || $opt->{s} || '.';
    $self->{for}         = $opt->{for}     || $opt->{f};
    $self->{log}         = $opt->{verbose} || $opt->{v};
}

sub execute {
    my $self = shift;

    $self->set_build_dir;

    # run the build (passing `self.program` because of recursion)
    $self->run_build( $self->{program} );
}

sub set_build_dir {
    my $self = shift;

    my $prefix_dir = path( $self->{build_dir}, 'main' );

    if ( ! -d $prefix_dir ) {
        $self->LOG("Creating build dir " . $self->{build_dir});
        make_path( $prefix_dir );
    }
}

sub run_build {
    my ( $self, $program_name, $prereqs ) = @_;

    # FIXME: we should have a config dir and a function that checks
    #        for the existence of config files in it
    # FIXME: the config class should have "mandatory" fields, add checks

    # read the configuration
    my $config;
    eval {
        $config = read_config(
            $self->{config_base},
            "$program_name.toml"
        );
        1;
    } or do {
        my $err = $@ || "error reading config file";
        $self->usage_error($err);
    };

    # double check we have the right program configuration
    my $config_name = $config->{'Package'}{'name'}
        or die "Program config must provide 'name'\n";

    my $config_category = $config->{'Package'}{'category'}
        or die "Program config must provide 'category'\n";

    $config_name eq $program_name
        or die "$program_name configuration claims it is $config_name\n";

    # FIXME: is this already built?
    # once we're done building something, we should be moving it over
    # to the "BUILT" directory (artifact repo) - then we can check if
    # a package is already available there

    # recursively build prereqs
    # starting with system libraries
    if ( my $system_prereqs = $config->{'Prereqs'}{'system'} ) {
        foreach my $prereq ( keys %{$system_prereqs} ) {
            my $prereq_opts = {
                %{$self},
                category => 'system',
                program  => $prereq,
            };
            $self->run_build( $prereq_opts, $prereq, $system_prereqs->{$prereq} );
        }
    }

    if ( my $perl_prereqs = $config->{'Prereqs'}{'perl'} ) {
        foreach my $prereq ( keys %{$perl_prereqs} ) {
            my $prereq_opts = {
                %{$self},
                category => 'perl',
                program  => $prereq,
            };
            $self->run_build( $self, $prereq, $perl_prereqs->{$prereq} );
        }
    }

    my $program_src_dir = $self->{source_base} . $config->{'Package'}{'directory'};

    $self->LOG('Copying program files');
    -d $program_src_dir
        or die "Cannot find source dir: $program_src_dir\n";

    my $top_build_dir = $self->{build_dir};

    my $pkgconfig_path = path( $top_build_dir, qw<main lib pkgconfig> );
    $self->LOG("Setting PKG_CONFIG_PATH=$pkgconfig_path");
    local $ENV{'PKG_CONFIG_PATH'} = $pkgconfig_path;

    my $main_build_dir = path( $top_build_dir, 'main' );
    $self->LOG("Setting LD_LIBRARY_PATH=$main_build_dir");
    local $ENV{'LD_LIBRARY_PATH'} = $main_build_dir;

    # FIXME: Remove in favor of a ::Build::System, ::Build::Perl, etc.
    # FIXME: $program_dst_dir is dictated from the category
    if ( $config_category eq 'system' ) {
        my $program_dst_dir = path(
            $top_build_dir,
            'libs',
            basename($program_src_dir),
        );

        dircopy( $program_src_dir, $program_dst_dir );

        $self->build_program(
            $program_name,    # zeromq
            $program_dst_dir, # /tmp/BUILD-1/libs/zeromq-1.4.1
            $main_build_dir,  # /tmp/BUILD-1/main
        );
    }
    elsif ( $config_category eq 'perl' ) {
        my $program_dst_dir = path(
            $top_build_dir,
            'perl_libs',
            basename($program_src_dir),
        );

        dircopy( $program_src_dir, $program_dst_dir );

        $self->build_perl_program(
            $program_name,    # ZMQ::Constants
            $program_dst_dir, # /tmp/BUILD-1/libs/ZMQ-Constants-...
            $main_build_dir,  # /tmp/BUILD-1/main
        );
    }
    else {
        die "Unrecognized category ($config_category), cannot build this.\n";
    }

    # FIXME: when to keep, when to clean up
    #        keep for now
    #$self->LOG("Removing build dir $build_dir");
    #remove_tree($build_dir);
}

sub build_program {
    my ( $self, $program, $build_dir, $prefix ) = @_;

    $self->LOG("Building $program");

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
    $self->LOG("Done preparing $program");
}

sub build_perl_program {
    my ( $self, $program, $build_dir, $prefix ) = @_;

    $self->LOG("Building Perl module: $program");

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
    $self->LOG("Done preparing $program");
}

sub read_config {
    my ( $config_dir, $program ) = @_;

    my $config_file = path(@_);
    -r $config_file
        or die "could not find package information ($config_file)\n";

    return TOML::Parser->new( strict_mode => 1 )->parse_file($config_file);
}

1;

__END__
