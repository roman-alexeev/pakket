#!perl
use strict;
use warnings;
use DDP;
use TOML qw< to_toml >;
use MetaCPAN::Client;
use Getopt::Long qw< :config no_ignore_case >;
use Path::Tiny qw< path >;

sub help {
    my $msg = shift;

    $msg and print "$msg\n";

    print << "_END_HELP";
$0 < --dist DIST | --module MODULE > [ --version VERSION ]

    dist        distribution
    module      module (the distribution will be found by this)
    version     specific release version (default: latest indexed)
    output-dir  directory to write the configuration to (TOML file)

_END_HELP

    exit;
}

GetOptions( \my %opts, 'help|h', 'dist=s', 'module=s', 'version=s',
    'output-dir=s' );

$opts{'dist'} || $opts{'module'}
    or help('Must provide dist or module');

$opts{'dist'} && $opts{'module'}
    and help('Must provide either dist or module');

# TODO: add --version

my $mcpan        = MetaCPAN::Client->new();
my $dist_name    = $opts{'dist'};
my $dist_version = $opts{'version'};

if ( my $module = $opts{'module'} ) {
    eval {
        $dist_name = $mcpan->module($module)->distribution;
        1;
    } or die "Cannot find module by name: '$module'\n";
}

my $dist = eval {
    $mcpan->distribution($dist_name);
}
    or die "Cannot find distribution by name: '$dist_name'\n"
    . "Is this a module?\n";

my $release
    = $dist_version
    ? $mcpan->release(
    {
        all =>
            [ { distribution => $dist_name }, { version => $dist_version } ]
    }
    )->next
    : $mcpan->release($dist_name);

$dist_version //= $release->version;

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
    = path( ( $opts{'output_dir'} ? $opts{'output_dir'} : Path::Tiny->cwd ),
    $dist_name, "$dist_version.toml" );

$output_file->parent->mkpath;
$output_file->spew( to_toml($package) );
