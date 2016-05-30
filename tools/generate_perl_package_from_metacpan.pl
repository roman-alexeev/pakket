#!perl
use strict;
use warnings;
use DDP;
use TOML qw< to_toml >;
use MetaCPAN::Client;
use Getopt::Long qw< :config no_ignore_case >;
use Path::Tiny qw< path >;
use Module::CPANfile;

sub help {
    my $msg = shift;

    $msg and print "$msg\n";

    print << "_END_HELP";
$0 INPUT OPTIONS

INPUT:
$0 --dist DIST
$0 --module MODULE
$0 --cpanfile FILE

OPTIONS:
$0 --version VERSION
$0 --min-version VERSION

    dist            distribution
    module          module (the distribution will be found by this)
    cpanfile        provide a cpanfile to read modules from
    version         specific release version
    min-version     minimal version, find this version or greater
    output-dir      directory to write the configuration to (TOML file)

Default is to get the latest version available on CPAN.

_END_HELP

    exit;
}

GetOptions( \my %opts, 'help|h', 'dist=s', 'module=s', 'cpanfile=s',
    'min-version=s', 'version=s', 'output-dir=s' )
    or exit;

$opts{'dist'} || $opts{'module'} || $opts{'cpanfile'}
    or help('Must provide "dist", "module", or "cpanfile"');

my $mcpan = MetaCPAN::Client->new();

my ( $dist_version, $min_version )
    = defined $opts{'min-version'}
    ? ( $opts{'min-version'}, 1 )
    : ( $opts{'version'}, 0 );

if ( my $module_name = $opts{'module'} ) {
    create_config_for( module => $module_name, $dist_version, $min_version );
} elsif ( my $dist_name = $opts{'dist'} ) {
    create_config_for( dist => $dist_name, $dist_version, $min_version );
} elsif ( my $file = $opts{'cpanfile'} ) {
    my $modules = read_cpanfile($file);
    foreach my $module_name ( %{$modules} ) {
        print "$module_name\n";

        #create_config_for( module => $module_name, $modules->{$module_name} );
    }
} else {
    help('Must provide either "dist", "module", or "cpanfile"');
}

sub create_config_for {
    my ( $type, $dist_name, $dist_version, $min_version ) = @_;

    if ( $type eq 'module' ) {
        my $module_name = $dist_name;
        eval {
            $dist_name = $mcpan->module($module_name)->distribution;
            1;
        } or die "Cannot find module by name: '$module_name'\n";
    }

    my $dist = eval { $mcpan->distribution($dist_name); }
        or die "Cannot find distribution by name: '$dist_name'\n"
        . "Is this a module?\n";

    my $release;
    if ($dist_version) {
        $release
            = $min_version
            ? $mcpan->all(
            'releases',
            {
                es_filter => {
                    and => [
                        { range => { version => { gte => $dist_version } } },
                        { term => { distribution => $dist_name } },
                    ],
                }
            }
            )->next
            : $mcpan->release(
            {
                all => [
                    { distribution => $dist_name },
                    { version      => $dist_version }
                ]
            }
            )->next;
    } else {
        $release = $mcpan->release($dist_name);
    }

    if ( !$release ) {
        warn "Cannot find $dist_name $dist_version"
            . ( $min_version ? ' or greater' : '' );
        return;
    }

    $dist_version = $release->version;
    print "Working on $dist_name ($dist_version)\n";

    my $release_prereqs = $release->metadata->{'prereqs'};

    my $package = {
        Package => {
            name     => $dist_name,
            category => 'perl',
            version  => $dist_version,
        },
    };

    # options: configure, develop, runtime, test
    foreach my $prereq_type (qw< configure runtime test >) {
        $package->{'Prereqs'}{'perl'}{$prereq_type} = +{
            map {
                ;
                my $prereq_level = $_;
                my $level_prereqs
                    = $release_prereqs->{$prereq_type}{$prereq_level};

                $level_prereqs
                    ? map +( $_ => { version => $level_prereqs->{$_} } ),
                    keys %{$level_prereqs}
                    : ()
            } qw< requires recommends suggests >
        };
    }

    my $output_file
        = path( 'perl', ( $opts{'output-dir'} ? $opts{'output-dir'} : '.' ),
        $dist_name, "$dist_version.toml" );

    $output_file->parent->mkpath;
    $output_file->spew( to_toml($package) );

}

sub read_cpanfile {
    my $filename = shift;
    my $file     = Module::CPANfile->load($filename);
    return {
        map {
            ;
            my $phase = $_;
            map %{ $file->{$phase}{$_} }, keys %{ $file->{$phase} };
        } keys %{$file}
    };
}
