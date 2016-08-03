#!perl
use strict;
use warnings;
use version;

use TOML qw< to_toml >;
use Getopt::Long::Descriptive;
use Path::Tiny qw< path >;
use Module::CPANfile;
use CPAN::Meta::Prereqs;
use JSON::MaybeXS qw< decode_json encode_json >;
use HTTP::Tiny;
use Archive::Any;
use Ref::Util qw< is_hashref >;

use Pakket::Utils qw< generate_json_conf >;

$|++;

# TODO: fix some annoying issues ###############################################
my %known_incorrect_name_fixes = (
    'App::Fatpacker'              => 'App::FatPacker',
    'Test::YAML::Meta::Version'   => 'Test::YAML::Meta', # not sure about this
    'Net::Server::SS::Prefork'    => 'Net::Server::SS::PreFork',
);
my %known_incorrect_version_fixes = (
    'ExtUtils-Constant'           => '0.23',
    'IO-Capture'                  => '0.05',
);
my %known_names_to_skip =  (
    'perl'                        => 1,
    'perl_mlb'                    => 1,
    'Text::MultiMarkdown::XS'     => 1, # ADOPTME
);

################################################################################
################################################################################

sub help {
    my $msg = shift;

    $msg and print "$msg\n";

    print << "_END_HELP";
$0 INPUT

INPUT:
$0 --cpanfile FILE

    cpanfile    provide a cpanfile to read modules from
    config-dir  directory to write the configuration to (TOML file)
    source-dir  directory to write the sources to (downloads if provided)
    json-file   file to generate json configuration to
    extract     extract downloaded source tarball (default=0)

_END_HELP

    exit;
}

my ( $opt, $usage ) = describe_options(
    "$0 %o",
    [ 'cpanfile=s',   'cpanfile to parse', { required => 1 } ],
    [ 'config-dir=s', 'directory to write the configuration to (TOML files)', { required => 1 } ],
    [ 'source-dir=s', 'directory to write the sources to (downloads if provided)', {} ],
    [ 'json-file=s',  'file to generate json configuration to', {} ],
    [ 'extract',      'extract downloaded source tarball', { default => 0 } ],
    [],
    [ 'help', 'Usage' ],
);

$opt->help
    and print $usage->text
    and exit;

my %processed_dists;
my $step = 0;
my $http = HTTP::Tiny->new();
my $metacpan_api_v1 = "https://fastapi.metacpan.org";
my $metacpan_api_v0 = "https://api.metacpan.org"; # temp. workaround

my $source_dir = $opt->source_dir ? path( $opt->source_dir ) : undef;

my $modules = read_cpanfile( $opt->cpanfile );
my $prereqs = CPAN::Meta::Prereqs->new( $modules );

for my $phase (qw< configure runtime >) {
    print "phase: $phase\n";
    for my $type (qw< requires recommends suggests >) {
        next unless is_hashref( $modules->{$phase}{$type} );

        my $requirements = $prereqs->requirements_for( $phase, $type );
        create_config_for( module => $_, $requirements )
            for sort keys %{ $modules->{$phase}{$type} };
    }
}

if ( $opt->json_file ) {
    generate_json_conf( $opt->json_file, $opt->config_dir );
}

1;

################################################################################


sub spaces {
    print ' ' x ( $step * 2 );
}

sub create_config_for {
    my ( $type, $name, $requirements ) = @_;
    return if exists $known_names_to_skip{$name};

    if ( $processed_dists{$name}++ ) {
        #spaces();
        #print "<= Already processed $name\n";
        return;
    }

    my $release = get_release_info($type, $name, $requirements);
    return if exists $release->{skip};

    spaces();
    $step++;

    my $dist_name    = $release->{'distribution'};
    my $rel_version  = $release->{'version'};
    my $download_url = $release->{'download_url'};
    print "-> Working on $dist_name ($rel_version)\n";

    my $conf_file = path( ( $opt->config_dir // '.' ),
                          'perl', $dist_name, "$rel_version.toml" );

    # download source if dir provided and file doesn't already exist
    if ( $source_dir ) {
        if ( $download_url ) {
            my $source_file = path( $source_dir, ( $download_url =~ s{^.+/}{}r ) );
            if ( !$source_file->exists ) {
                $source_file->parent->mkpath;
                $http->mirror( $download_url, $source_file );
            }
            if ( $opt->extract ) {
                my $archive = Archive::Any->new( $source_file );
                $archive->extract( $source_dir );
                $source_file->remove;
            }
        }
        else {
            print "--- can't find download_url for $dist_name-$rel_version\n";
        }
    }

    if ( $conf_file->exists ) {
        #print "<= config file exists for $name\n";
        $step--;
        return;
    }

    my $package = {
        Package => {
            category => 'perl',
            name     => $dist_name,
            version  => $rel_version,
        },
    };

    my $dep_modules = $release->{'prereqs'};
    my $dep_prereqs = CPAN::Meta::Prereqs->new( $dep_modules );

    # options: configure, develop, runtime, test
    for my $phase (qw< configure runtime >) {
        for my $dep_type (qw< requires recommends suggests >) {
            next unless is_hashref( $dep_modules->{$phase}{$dep_type} );

            my $prereq_data = $package->{'Prereqs'}{'perl'}{$dep_type} = +{};
            my $dep_requirements = $dep_prereqs->requirements_for( $phase, $dep_type );

            for my $module ( keys %{ $dep_modules->{$phase}{$dep_type} } ) {
                next if exists $known_names_to_skip{$module};

                my $rel = get_release_info( module => $module, $dep_requirements );
                next if exists $rel->{skip};

                $prereq_data->{ $rel->{distribution} } = +{
                    version => ( $rel->{write_version_as_zero} ? 0 : $rel->{version} )
                };
            }

            # recurse through those as well
            create_config_for( dist => $_, $dep_requirements )
                for keys %{ $package->{'Prereqs'}{'perl'}{$dep_type} };
        }
    }

    $step--;

    $conf_file->parent->mkpath;
    $conf_file->spew( to_toml($package) );
}

sub get_dist_name {
    my $module_name = shift;
    $module_name = $known_incorrect_name_fixes{$module_name}
        if exists $known_incorrect_name_fixes{$module_name};

    my $dist_name;
    eval {
        my $response = $http->get( $metacpan_api_v1 . "/module/$module_name" );
        # temp workaround:
        if ( $response->{status} != 200 ) {
            print "--- couldn't find /module/$module_name on v1, falling back to v0\n";
            $response = $http->get( $metacpan_api_v0 . "/module/$module_name" );
        }
        die if $response->{status} != 200;
        my $content = decode_json $response->{content};
        $dist_name  = $content->{distribution};
        1;
    } or die "-> Cannot find module by name: '$module_name'\n";
    return $dist_name;
}

sub _get_latest_release_info {
    my $dist_name = shift;

    my $res = $http->get("https://fastapi.metacpan.org/v1/release/$dist_name");
    return unless $res->{status} == 200; # falling back to check all

    my $res_body= decode_json $res->{content};

    return +{
        distribution => $dist_name,
        version      => $res_body->{version},
        download_url => $res_body->{download_url},
        prereqs      => $res_body->{metadata}{prereqs},
    };
}

sub get_release_info {
    my ( $type, $name, $requirements ) = @_;

    my $dist_name = $type eq 'module'
        ? get_dist_name($name)
        : $name;

    return +{ skip => 1 } if exists $known_names_to_skip{$dist_name};

    my $req_as_hash = $requirements->as_string_hash;
    my $write_version_as_zero = !!(
        defined $req_as_hash->{$name}
        and version->parse( $req_as_hash->{$name} =~ s/[^0-9.]//gr ) == 0
    );

    # first try the latest (temp. v1 only)

    my $latest = _get_latest_release_info( $dist_name );
    $latest->{write_version_as_zero} = $write_version_as_zero;
    return $latest
        if defined $latest->{version}
           and defined $latest->{download_url}
           and $requirements->accepts_module($name => $latest->{version});

    # else: fetch all release versions for this distribution

    my $release_prereqs;
    my $version;
    my $download_url;

    my %all_dist_releases;
    {
        my $res = $http->post( $metacpan_api_v1 . "/release",
                               +{ content => _get_release_query($dist_name, 'v1') });
        # temp. workaround
        my $key = '_source';
        if ( $res->{status} != 200 ) {
            print "--- couldn't find 'release' info for $dist_name on v1, falling back to v0\n";
            $res = $http->post( $metacpan_api_v0 . "/release",
                                +{ content => _get_release_query($dist_name, 'v0') });
            $key = 'fields';

        }
        die "can't find any release for $dist_name\n" if $res->{status} != 200;
        my $res_body = decode_json $res->{content};

        %all_dist_releases =
            map {
                $_->{fields}{version}[0] => {
                    prereqs      => $_->{$key}{metadata}{prereqs},
                    download_url => $_->{$key}{download_url},
                }
            }
            @{ $res_body->{hits}{hits} };
    }

    # get the matching version according to the spec

    for my $v ( sort { version->parse($b) <=> version->parse($a) } keys %all_dist_releases ) {
        if ( $requirements->accepts_module($name => $v) ) {
            $version         = $v;
            $release_prereqs = $all_dist_releases{$v}{prereqs} || {};
            $download_url    = $all_dist_releases{$v}{download_url};
            last;
        }
    }
    $version or die "Cannot match release for $dist_name\n";

    $version = $known_incorrect_version_fixes{$dist_name}
        if exists $known_incorrect_version_fixes{$dist_name};

    return +{
        distribution          => $dist_name,
        version               => $version,
        prereqs               => $release_prereqs,
        download_url          => $download_url,
        write_version_as_zero => $write_version_as_zero,
    };
}

sub _get_release_query {
    my $dist_name = shift;
    my $version   = shift; # temp. workaround

    return encode_json({
        query  => {
            bool => {
                must => [
                    { term  => { distribution => $dist_name } },
                    { terms => { status => [qw< cpan latest >] } }
                ]
            }
        },
        $version eq 'v1'
            ? ( fields  => [qw< version >],
                _source => [qw< metadata.prereqs download_url >] )
            : ( fields  => [qw< version metadata >] ),
        size    => 999,
    });
}

sub read_cpanfile {
    my $filename = shift;
    my $file     = Module::CPANfile->load($filename);
    return $file->prereq_specs;
}
