#!/usr/bin/perl

use strict;
use warnings;
use TOML qw< from_toml >;
use Pakket::Package;
use Pakket::Repository::Config;
use Path::Tiny qw< path >;
use Log::Any::Adapter;
use Log::Dispatch;

Log::Any::Adapter->set(
    'Dispatch', 'dispatcher' => Log::Dispatch->new(
        'outputs' => [
            [ 'Screen', 'min_level' => 'debug' ],
        ],
    ),
);

my ( $prev_config_dir, $repo_config_dir ) = @ARGV;
$prev_config_dir && $repo_config_dir
    or die "$0 <config dir> <repo config dir>\n";

my $base_path   = path($prev_config_dir);
my $config_repo = Pakket::Repository::Config->new(
    'directory' => $repo_config_dir,
);

my $total = 0;

foreach my $category (qw< native perl >) {
    my @packages = $base_path->child($category)->children;
    foreach my $package_path (@packages) {
        my $package_name = $package_path->basename;

        $package_path->visit(
            sub {
                my $path     = shift;
                my $config   = from_toml( $path->slurp_utf8 );
                my $package  = Pakket::Package->new_from_config($config);
                my $filename = $config_repo->store_package_config($package);

                $total++;

                print "* Stored ", $package->full_name, " as $filename\n";
            },
            { 'recurse' => 1 },
        );
    }
}

print "* Imported $total files. Done.\n";
