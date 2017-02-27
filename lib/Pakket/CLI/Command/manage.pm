package Pakket::CLI::Command::manage;
# ABSTRACT: The pakket manage command

use strict;
use warnings;
use Log::Any::Adapter;
use Path::Tiny qw< path  >;
use List::Util qw< first >;

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
        # TODO
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
        'spec'   => 'spec_dir',
        'source' => 'source_dir',
    );

    foreach my $type ( keys %map ) {
        my $opt_key   = $map{$type};
        my $directory = $opt->{$opt_key};

        if ($directory) {
            $config->{'repositories'}{$type} = [
                'File', 'directory' => $directory,
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

    my $command = shift @{$args};
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

    my ( $category, $name, $version ) = $spec_str =~ PAKKET_PACKAGE_SPEC()
        or $self->usage_error("Provide category/name[=version], not '$spec_str'");

    first { $_ eq $category } qw< perl > # add supported categories
        or $self->usage_error( "Wrong 'name' format\n" );

    $self->{'category'} = $category;
    $self->{'module'}   = +{
        name    => $name,
        version => $version,
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
        push @params => ( 'cpanfile' => $self->{'cpanfile'} );
    } else {
        push @params => (
            'module'  => $self->{'module'}{'name'},
             # hack to pass exact version in prereq syntax
            'version' => '=='.$self->{'module'}{'version'},
        );
    }

    my $from_dir = $self->{'from_dir'};
    $from_dir and push @params => ( 'from_dir' => $from_dir );

    return Pakket::Scaffolder::Perl->new(@params);
}

1;
__END__
