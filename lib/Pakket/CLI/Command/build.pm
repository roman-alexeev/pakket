package Pakket::CLI::Command::build;
# ABSTRACT: Build a Pakket package

use strict;
use warnings;

use Pakket::CLI '-command';
use Pakket::Constants qw< PAKKET_PACKAGE_SPEC PAKKET_LATEST_VERSION >;
use Pakket::Builder;
use Pakket::Requirement;
use Pakket::Log;           # predefined loggers

use Path::Tiny qw< path >;
use Log::Any   qw< $log >; # to log
use Log::Any::Adapter;     # to set the logger

# TODO:
# - move all hardcoded values (confs) to constants
# - add make process log (and add it with -v -v)
# - check all operations (chdir, mkpath, etc.) (move() already checked)
# - should we detect a file change during BUILD and die/warn?
# - stop calling system(), use a proper Open module instead so we can
#   easily check the success/fail and protect against possible injects

# FIXME: pass on the "output-dir" to the bundler

sub abstract    { 'Build a package' }
sub description { 'Build a package' }

sub opt_spec {
    return (
        [ 'category=s',     'build only this key the index' ],
        [ 'input-file=s',   'build stuff from this file' ],
        [ 'skip=s',         'skip this index entry' ],
        [ 'build-dir=s',    'use an existing build directory' ],
        [ 'keep-build-dir', 'do not delete the build directory' ],
        [
            'config-dir=s',
            'directory holding the configurations',
            { 'required' => 1 },
        ],
        [
            'source-dir=s',
            'directory holding the sources',
            { 'required' => 1 },
        ],
        [ 'output-dir=s', 'output directory (default: .)' ],
        [ 'verbose|v+',   'verbose output (can be provided multiple times)' ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    Log::Any::Adapter->set(
        'Dispatch',
        'dispatcher' => Pakket::Log->build_logger( $opt->{'verbose'} ),
    );

    # Check that the directory for configs exists
    # (How do we get it from the CLI?)
    my $config_dir = path( $opt->{'config_dir'} );
    $config_dir->exists && $config_dir->is_dir
        or $self->usage_error("Incorrect config directory specified: '$config_dir'");
    $self->{'builder'}{'config_dir'} = $config_dir;

    if ( defined ( my $output_dir = $opt->{'output_dir'} ) ) {
        $self->{'bundler'}{'bundle_dir'} = path($output_dir)->absolute;
        $self->{'builder'}{'parcel_dir'} = $output_dir;
    }

    my @specs;
    if ( defined ( my $file = $opt->{'input_file'} ) ) {
        my $path = path($file);
        $path->exists && $path->is_file
            or $self->usage_error("Bad input file: $path");

        push @specs, $path->lines_utf8( { 'chomp' => 1 } );
    } elsif ( @{$args} ) {
        @specs = @{$args};
    } else {
        $self->usage_error('Must specify at least one package or a file');
    }

    foreach my $spec_str (@specs) {
        my ( $cat, $name, $version ) = $spec_str =~ PAKKET_PACKAGE_SPEC()
            or $self->usage_error("Provide category/name, not '$spec_str'");

        my $req;
        eval { $req = Pakket::Requirement->new_from_string($spec_str); 1; }
        or do {
            my $error = $@ || 'Zombie';
            $log->debug("Failed to create Pakket::Requirement: $error");
            $self->usage_error(
                "We do not understand this package string: $spec_str",
            );
        };

        push @{ $self->{'to_build'} }, $req;
    }

    if ( $opt->{'build_dir'} ) {
        -d $opt->{'build_dir'}
            or die "You asked to use a build dir that does not exist.\n";

        $self->{'builder'}{'build_dir'} = $opt->{'build_dir'};
    }

    $self->{'builder'}{'keep_build_dir'} = $opt->{'keep_build_dir'};

    # XXX These will get removed eventually
    $self->{'builder'}{'config_dir'} = $opt->{'config_dir'};
    $self->{'builder'}{'source_dir'} = $opt->{'source_dir'};
}

sub execute {
    my $self    = shift;
    my $builder = Pakket::Builder->new(
        # default main object
        map( +(
            defined $self->{'builder'}{$_}
                ? ( $_ => $self->{'builder'}{$_} )
                : ()
        ), qw< parcel_dir config_dir source_dir build_dir keep_build_dir > ),

        # bundler args
        'bundler_args' => {
            map( +(
                defined $self->{'bundler'}{$_}
                    ? ( $_ => $self->{'bundler'}{$_} )
                    : ()
            ), qw< bundle_dir > ),
        },
    );

    foreach my $prereq ( @{ $self->{'to_build'} } ) {
        $builder->build($prereq);
    }
}

1;

__END__
