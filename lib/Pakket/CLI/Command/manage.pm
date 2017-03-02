package Pakket::CLI::Command::manage;
# ABSTRACT: The pakket manage command

use strict;
use warnings;

use Path::Tiny qw< path  >;
use List::Util qw< first >;
use Log::Any   qw< $log >; # to log
use Log::Any::Adapter;     # to set the logger

use Pakket::CLI '-command';
use Pakket::Log;
use Pakket::Config;
use Pakket::Scaffolder::Perl;
use Pakket::Constants qw< PAKKET_PACKAGE_SPEC >;

sub abstract    { 'Scaffold a project' }
sub description { 'Scaffold a project' }

sub opt_spec {
    return (
        [ 'cpanfile=s',   'cpanfile to configure from' ],
        [ 'spec-dir=s',   'directory to write the spec to (JSON files)' ],
        [ 'source-dir=s', 'directory to write the sources to (downloads if provided)' ],
        [ 'from-dir=s',   'directory to get sources from (optional)' ],
        [ 'additional_phase=s@',
          "additional phases to use ('develop' = author_requires, 'test' = test_requires). configure & runtime are done by default.",
        ],
        [ 'config|c=s',   'configuration file' ],
        [ 'verbose|v+',   'verbose output (can be provided multiple times)' ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    Log::Any::Adapter->set(
        'Dispatch',
        'dispatcher' => Pakket::Log->build_logger( $opt->{'verbose'} ),
    );

    $self->_determine_config($opt);
    $self->_validate_arg_command($args);
    $self->_validate_arg_from_dir($opt);

    $self->{'command'} eq 'add'
        and $self->_validate_args_add( $opt, $args );

    $self->{'command'} eq 'remove'
        and $self->_validate_args_remove( $opt, $args );
}

sub execute {
    my $self = shift;

    if ( $self->{'command'} eq 'add' ) {
        $self->_get_scaffolder->run;
    } elsif ( $self->{'command'} eq 'remove' ) {
        my $package = Pakket::Package->new(
            'category' => $self->{'category'},
            'name'     => $self->{'module'}{'name'},
            'version'  => $self->{'module'}{'version'},
            'release'  => $self->{'module'}{'release'},
        );

        # TODO: check we are allowed to remove package (dependencies)

        $self->remove_package_spec($package);
        $self->remove_package_source($package);
    }
}


sub _determine_config {
    my ( $self, $opt ) = @_;

    my $config_file   = $opt->{'config'};
    my $config_reader = Pakket::Config->new(
        $config_file ? ( 'files' => [$config_file] ) : (),
    );

    my $config = $config_reader->read_config;

    my %map = (
        'spec'   => [ 'spec_dir',   'ini' ],
        'source' => [ 'source_dir', 'spkt' ],
    );

    foreach my $type ( keys %map ) {
        my ( $opt_key, $opt_ext ) = @{ $map{$type} };
        my $directory = $opt->{$opt_key};

        if ($directory) {
            $config->{'repositories'}{$type} = [
                'File',
                'directory'      => $directory,
                'file_extension' => $opt_ext,
            ];

            my $path = path($directory);
            $path->exists && $path->is_dir
                or $self->usage_error("Bad directory for $type repo: $path");
        }

        if ( !$config->{'repositories'}{$type} ) {
            $self->usage_error("Missing configuration for $type repository");
        }
    }

    $self->{'config'} = $config;
}

sub _validate_arg_command {
    my ( $self, $args ) = @_;

    my $command = shift @{$args}
        or $self->usage_error("Must pick action (add/remove/replace)");

    grep { $command eq $_ } qw< add remove replace >
        or $self->usage_error( "Wrong command (add/remove/replace)\n" );

    $self->{'command'} = $command;
}

sub _validate_arg_from_dir {
    my ( $self, $opt ) = @_;

    my $from_dir = $opt->{'from_dir'};

    if ( $from_dir ) {
        path( $from_dir )->exists
            or $self->usage_error( "from-dir: $from_dir doesn't exist\n" );
        $self->{'from_dir'} = $from_dir;
    }
}

sub _validate_args_add {
    my ( $self, $opt, $args ) = @_;

    my $cpanfile = $opt->{'cpanfile'};
    my $spec_str = shift @{$args};

    !@{$args} and ( !!$cpanfile xor !!$spec_str )
        or $self->usage_error( "Must provide a single package id or a cpanfile (not both)" );

    if ( $cpanfile ) {
        $self->{'category'} = 'perl';
        $self->{'cpanfile'} = $cpanfile;
    } else {
        $self->_read_arg_package($spec_str);
    }
}

sub _validate_args_remove {
    my ( $self, $opt, $args ) = @_;

    my $spec_str = shift @{$args};

    $spec_str
        or $self->usage_error( "Must provide a package id to remove" );

    $self->_read_arg_package($spec_str);
}

sub _read_arg_package {
    my ( $self, $spec_str ) = @_;

    my ( $category, $name, $version, $release ) = $spec_str =~ PAKKET_PACKAGE_SPEC()
        or $self->usage_error("Provide category/name[=version:release], not '$spec_str'");

    first { $_ eq $category } qw< perl > # add supported categories
        or $self->usage_error( "Wrong 'name' format\n" );

    $self->{'category'} = $category;
    $self->{'module'}   = +{
        name    => $name,
        version => $version,
        release => $release || 1,
    };
}

sub _get_scaffolder {
    my $self = shift;

    $self->{'category'} eq 'perl'
        and return $self->_gen_scaffolder_perl;

    die "failed to create a scaffolder\n";
}

sub _gen_scaffolder_perl {
    my $self = shift;

    my @params = ( 'config' => $self->{'config'} );

    if ( $self->{'cpanfile'} ) {
        push @params =>
            ( 'cpanfile' => $self->{'cpanfile'} );

    } else {
        my $version = $self->{'module'}{'version'}
            # hack to pass exact version in prereq syntax
            ? '=='.$self->{'module'}{'version'}
            : undef;

        push @params => (
            'module'  => $self->{'module'}{'name'},
            'version' => $version,
        );
    }

    my $from_dir = $self->{'from_dir'};
    $from_dir and push @params => ( 'from_dir' => $from_dir );

    return Pakket::Scaffolder::Perl->new(@params);
}

sub remove_package_source {
    my ( $self, $package ) = @_;
    my $source_repo = Pakket::Repository::Source->new(
        'backend' => $self->{'config'}{'repositories'}{'source'},
    );
    $source_repo->remove_package_source( $package );
    $log->info( sprintf("Removed %s from the source repo.", $package->id ) );
}

sub remove_package_spec {
    my ( $self, $package ) = @_;
    my $spec_repo = Pakket::Repository::Spec->new(
        'backend' => $self->{'config'}{'repositories'}{'spec'},
    );
    $spec_repo->remove_package_spec( $package );
    $log->info( sprintf("Removed %s from the spec repo.", $package->id ) );
}

1;
__END__
