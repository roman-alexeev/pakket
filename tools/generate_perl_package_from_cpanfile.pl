#!perl
use strict;
use warnings;
use version;
use TOML qw< to_toml >;
use Getopt::Long qw< :config no_ignore_case >;
use Path::Tiny qw< path >;
use Module::CPANfile;
use JSON::MaybeXS qw< decode_json encode_json >;
use HTTP::Tiny;

$|++;

# TODO: fix some annoying issues ####################################################
my %known_incorrect_name_fixes = (
    'App::Fatpacker'              => 'App::FatPacker',
    'Test::YAML::Meta::Version'   => 'Test::YAML::Meta', # not sure about this one
    'Net::Server::SS::Prefork'    => 'Net::Server::SS::PreFork',
);
my %known_incorrect_version_fixes = (
    'ExtUtils-Constant'           => '0.23',
    'IO-Capture'                  => '0.05',
);
my %known_module_names_to_skip =  (
    'perl'                        => 1,
    'Text::MultiMarkdown::XS'     => 1, # ADPOTME
);

#####################################################################################

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

_END_HELP

    exit;
}

GetOptions( \my %opts, 'help|h', 'cpanfile=s', 'config-dir=s', 'source-dir=s' )
    or exit;

$opts{'cpanfile'} or help('Must provide "cpanfile"');

my %processed_dists;
my $step = 0;
my $http = HTTP::Tiny->new();
my $metacpan_api_v1 = "https://fastapi.metacpan.org";
my $metacpan_api_v0 = "https://api.metacpan.org"; # temp. workaround

my $source_dir = $opts{'source-dir'} ? path( $opts{'source-dir'} ) : undef;

my $modules = read_cpanfile( $opts{'cpanfile'} );
my $prereqs = CPAN::Meta::Prereqs->new( $modules );

for my $phase ( sort keys %{ $modules } ) {
    print "phase: $phase\n";
    for my $type ( sort keys %{ $modules->{$phase} } ) {
        my $requirements = $prereqs->requirements_for( $phase, $type );
        create_config_for( module => $_, $requirements )
            for sort keys %{ $modules->{$phase}{$type} };
    }
}

sub spaces {
    print ' ' x ( $step * 2 );
}

sub create_config_for {
    my ( $type, $name, $requirements ) = @_;
    return if exists $known_module_names_to_skip{$name};

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

    my $conf_file = path( ( $opts{'config-dir'} // '.' ),
                          'perl', $dist_name, "$rel_version.toml" );

    # download source if dir provided and file doesn't already exist
    if ( $source_dir ) {
        if ( $download_url ) {
            my $source_file = path( $source_dir, ( $download_url =~ s{^.+/}{}r ) );
            if ( !$source_file->exists ) {
                $source_file->parent->mkpath;
                $http->mirror( $download_url, $source_dir->parent . '/' . $source_file );
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

    my $release_prereqs = $release->{'prereqs'};

    # options: configure, develop, runtime, test
    # we don't use "develop" - those are tools like dzil
    for my $prereq_type (qw< configure runtime test >) {
        my $prereq_data = $package->{'Prereqs'}{'perl'}{$prereq_type} = +{};

        for my $prereq_level (qw<requires recommends suggests>) {
            my $level_prereqs = $release_prereqs->{$prereq_type}{$prereq_level};

            for my $module ( keys %{ $level_prereqs } ) {
                next if exists $known_module_names_to_skip{$module};
                my $rel = get_release_info( module => $module, $requirements );
                next if exists $rel->{skip};
                $prereq_data->{ $rel->{distribution} } = +{ version => $rel->{version} };
            }
        }

        # recurse through those as well
        for ( keys %{ $package->{'Prereqs'}{'perl'}{$prereq_type} } ) {
            create_config_for( dist => $_, $requirements );
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

    return +{ skip => 1 } if $dist_name eq 'perl';
    return +{ skip => 1 } if $dist_name eq 'perl_mlb';

    # first try the latest (temp. v1 only)

    my $latest = _get_latest_release_info( $dist_name );
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
        distribution => $dist_name,
        version      => $version,
        prereqs      => $release_prereqs,
        download_url => $download_url,
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
