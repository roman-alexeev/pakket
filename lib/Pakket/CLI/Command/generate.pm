package Pakket::CLI::Command::generate;
# ABSTRACT: The pakket install command

use strict;
use warnings;
use Log::Any::Adapter;
use Path::Tiny qw< path  >;
use List::Util qw< first >;

use Pakket::CLI '-command';
use Pakket::Log;
use Pakket::Config;
use Pakket::Scaffolder::Perl;

sub abstract    { 'Scaffold a project' }
sub description { 'Scaffold a project' }

sub opt_spec {
    return (
        [
            'name=s',
            'category/module name (e.g. "perl/Moose")',
        ],
        [
            'cpanfile=s',
            'cpanfile to configure from',
        ],
        [
            'spec-dir=s',
            'directory to write the spec to (JSON files)',
        ],
        [
            'source-dir=s',
            'directory to write the sources to (downloads if provided)',
        ],
        [
            'from-dir=s',
            'directory to get sources from (optional)',
        ],
        [
            'additional_phase=s@',
            "additional phases to use ('develop' = author_requires, 'test' = test_requires). configure & runtime are done by default.",
        ],
        [ 'config|c=s',     'configuration file' ],
        [ 'verbose|v+',     'verbose output (can be provided multiple times)' ],
    );
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

    return $config;
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    Log::Any::Adapter->set(
        'Dispatch',
        'dispatcher' => Pakket::Log->build_logger( $opt->{'verbose'} ),
    );

    @{ $args } and $self->usage_error("No extra arguments are allowed.\n");

    $opt->{'config'} = $self->_determine_config($opt);

    my $from_dir = $opt->{'from_dir'};
    if ( $from_dir ) {
        path( $from_dir )->exists
            or $self->usage_error( "from-dir: $from_dir doesn't exist\n" );
    }

    my $category;
    my $name;
    my $type;

    if ( $opt->{'name'} ) {
        ( $category, $name ) = split /\//xms => $opt->{'name'};
        first { $_ eq $category } qw< perl > # add supported categories
            or $self->usage_error( "Wrong 'name' format\n" );
        $type = 'module';
    }
    elsif ( $opt->{'cpanfile'} ) {
        $category = 'perl';
        $name     = $opt->{'cpanfile'};
        $type     = 'cpanfile';
    }
    else {
        $self->usage_error( "Must provide 'name' or 'cpanfile'\n" ); # future: others
    }

    @{$opt}{ qw< name category type > } = ( $name, $category, $type );
}

sub execute {
    my ( $self, $opt ) = @_;
    my $scaffolder = $self->_get_scaffolder($opt);
    $scaffolder->run;
}

sub _get_scaffolder {
    my ( $self, $opt ) = @_;
    $opt->{'category'} eq 'perl'
        and return $self->gen_scaffolder_perl($opt);
    die "failed to create a scaffolder\n";
}

sub gen_scaffolder_perl {
    my ( $self, $opt ) = @_;

    my $from_dir = $opt->{'config'}{'from_dir'};
    my @from_dir = $from_dir ? ( from_dir => $from_dir ) : ();

    return Pakket::Scaffolder::Perl->new(
        'config'       => $opt->{'config'},
        'extract'      => $opt->{'extract'},
        $opt->{'type'} => $opt->{'name'},
        @from_dir,
    );
}

1;
__END__
