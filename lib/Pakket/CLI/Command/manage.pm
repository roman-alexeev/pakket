package Pakket::CLI::Command::manage;
# ABSTRACT: The pakket manage command

use strict;
use warnings;

use Path::Tiny qw< path  >;
use List::Util qw< first >;
use Ref::Util  qw< is_arrayref >;
use Log::Any   qw< $log >; # to log
use Log::Any::Adapter;     # to set the logger

use Pakket::CLI '-command';
use Pakket::Log;
use Pakket::Config;
use Pakket::Scaffolder::Perl;
use Pakket::Manager;
use Pakket::Constants qw<
    PAKKET_PACKAGE_SPEC
    PAKKET_VALID_PHASES
>;

sub abstract    { 'Scaffold a project' }
sub description { 'Scaffold a project' }

sub opt_spec {
    return (
        [ 'cpanfile=s',   'cpanfile to configure from' ],
        [ 'spec-dir=s',   'directory to write the spec to (JSON files)' ],
        [ 'source-dir=s', 'directory to write the sources to (downloads if provided)' ],
        [ 'parcel-dir=s', 'directory where build output (parcels) are' ],
        [ 'cache-dir=s',  'directory to get sources from (optional)' ],
        [ 'additional-phase=s@',
          "additional phases to use ('develop' = author_requires, 'test' = test_requires). configure & runtime are done by default.",
        ],
        [ 'config|c=s',   'configuration file' ],
        [ 'verbose|v+',   'verbose output (can be provided multiple times)' ],
        [ 'add=s%',       '(deps) add the following dependency (phase=category/name=version[:release])' ],
        [ 'remove=s%',    '(deps) add the following dependency (phase=category/name=version[:release])' ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    Log::Any::Adapter->set(
        'Dispatch',
        'dispatcher' => Pakket::Log->build_logger( $opt->{'verbose'} ),
    );

    $self->{'opt'}  = $opt;
    $self->{'args'} = $args;

    $self->_determine_config;
    $self->_validate_arg_command;
    $self->_validate_arg_cache_dir;
}

sub execute {
    my $self = shift;
    my $package;

    my $command = $self->{'command'};

    if ( $command =~ /^(?:add|remove|deps|show)$/ ) {
        $package = Pakket::Package->new(
            'category' => $self->{'category'},
            'name'     => $self->{'module'}{'name'},
            'version'  => $self->{'module'}{'version'},
            'release'  => $self->{'module'}{'release'},
        );
    }

    my $manager = Pakket::Manager->new(
        config    => $self->{'config'},
        cpanfile  => $self->{'cpanfile'},
        cache_dir => $self->{'cache_dir'},
        phases    => $self->{'gen_phases'},
        package   => $package,
    );

    if ( $command eq 'add' ) {
        $manager->add_package($package);

    } elsif ( $command eq 'remove' ) {
        # TODO: check we are allowed to remove package (dependencies)
        $manager->remove_package_spec($package);
        $manager->remove_package_source($package);

    } elsif ( $command eq 'deps' ) {
        $self->{'deps_action'} eq 'add'
            and $manager->add_package_dependency($package, $self->{'dependency'});

        $self->{'deps_action'} eq 'remove'
            and $manager->remove_package_dependency($package, $self->{'dependency'});

    } elsif ( $command eq 'list' ) {
        $manager->list_ids( $self->{'list_type'} );

    } elsif ( $command eq 'show' ) {
        $manager->show_package_config($package);
    }
}


sub _determine_config {
    my $self = shift;
    my $opt  = $self->{'opt'};

    my $config_file   = $opt->{'config'};
    my $config_reader = Pakket::Config->new(
        $config_file ? ( 'files' => [$config_file] ) : (),
    );

    my $config = $config_reader->read_config;

    my %map = (
        'spec'   => [ 'spec_dir',   'ini' ],
        'source' => [ 'source_dir', 'spkt' ],
        'parcel' => [ 'parcel_dir', 'pkt' ],
    );

    foreach my $type ( keys %map ) {
        next if $type eq 'parcel' and !$opt->{'parcel_dir'};

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
    my $self = shift;

    my $command = shift @{ $self->{'args'} }
        or $self->usage_error("Must pick action (add/remove/deps/list/show)");

    grep { $command eq $_ } qw< add remove deps list show >
        or $self->usage_error( "Wrong command (add/remove/deps/list/show)" );

    $self->{'command'} = $command;

    $command eq 'add'    and $self->_validate_args_add;
    $command eq 'remove' and $self->_validate_args_remove;
    $command eq 'deps'   and $self->_validate_args_dependency;
    $command eq 'list'   and $self->_validate_args_list;
    $command eq 'show'   and $self->_validate_args_show;
}

sub _validate_arg_cache_dir {
    my $self = shift;

    my $cache_dir = $self->{'opt'}{'cache_dir'};

    if ( $cache_dir ) {
        path( $cache_dir )->exists
            or $self->usage_error( "cache-dir: $cache_dir doesn't exist\n" );
        $self->{'cache_dir'} = $cache_dir;
    }
}

sub _validate_args_add {
    my $self = shift;

    my $cpanfile = $self->{'opt'}{'cpanfile'};
    my $additional_phase = $self->{'opt'}{'additional_phase'};

    if ( $cpanfile ) {
        $self->{'category'} = 'perl';
        $self->{'cpanfile'} = $cpanfile;
    } else {
        $self->_read_set_spec_str;
    }

    # TODO: config ???
    $self->{'gen_phases'} = [qw< configure runtime >];
    if ( is_arrayref($additional_phase) ) {
        exists PAKKET_VALID_PHASES->{$_} or $self->usage_error( "Unsupported phase: $_" )
            for @{ $additional_phase };
        push @{ $self->{'gen_phases'} } => @{ $additional_phase };
    }
}

sub _validate_args_remove {
    my $self = shift;
    $self->_read_set_spec_str;
}

sub _validate_args_dependency {
    my $self = shift;
    my $opt  = $self->{'opt'};

    # spec
    $self->_read_set_spec_str;

    # dependency
    my $action = $opt->{'add'} || $opt->{'remove'};
    $action or $self->usage_error( "Missing arg: add/remove (mandatory for 'deps')" );

    my ( $phase, $dep_str ) = %{ $action };
    $phase or $self->usage_error( "Invalid dependency: missing phase" );
    my $dep = $self->_read_spec_str($dep_str);
    defined $dep->{'version'}
        or $self->usage_error( "Invalid dependency: missing version" );
    $dep->{'phase'} = $phase;

    $self->{'dependency'}  = $dep;
    $self->{'deps_action'} = $opt->{'add'} ? 'add' : 'remove';
}

sub _validate_args_list {
    my $self = shift;

    my $type = shift @{ $self->{'args'} };

    $type and grep { $type eq $_ } qw< parcels specs sources >
        or $self->usage_error( "Invalid type of list (parcels/specs/sources): " . ($type||"") );

    $type eq 'parcels' and !$self->{'opt'}{'parcel_dir'}
        and $self->usage_error( "You muse provide arg --parcel-dir to list parcels." );

    $self->{'list_type'} = $type =~ s/s$//r;
}

sub _validate_args_show {
    my $self = shift;
    $self->_read_set_spec_str;
}

sub _read_spec_str {
    my ( $self, $spec_str ) = @_;

    my ( $category, $name, $version, $release ) = $spec_str =~ PAKKET_PACKAGE_SPEC()
        or $self->usage_error("Provide [phase=]category/name[=version:release], not '$spec_str'");

    first { $_ eq $category } qw< perl native > # add supported categories
        or $self->usage_error( "Wrong 'name' format\n" );

    return +{
        category => $category,
        name     => $name,
        version  => $version,
        release  => $release || 1,
    };
}

sub _read_set_spec_str {
    my $self = shift;

    my $spec_str = shift @{ $self->{'args'} };
    $spec_str or $self->usage_error( "Must provide a package id (category/name=version:release)" );
    $self->{'cpanfile'}
        and $self->usage_error( "You can't provide both a cpanfile and a package id." );

    my $spec = $self->_read_spec_str($spec_str);
    $self->{'category'} = delete $spec->{'category'};
    $self->{'module'}   = $spec;
}

1;
__END__
