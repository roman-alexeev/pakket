#!/usr/bin/perl

use strict;
use warnings;
use TOML qw< from_toml >;
use Pakket::Package;
use Pakket::Repository::Spec;
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

my ( $prev_spec_dir, $repo_spec_dir ) = @ARGV;
$prev_spec_dir && $repo_spec_dir
    or die "$0 <spec dir> <repo spec dir>\n";

my $base_path   = path($prev_spec_dir);
my $spec_repo = Pakket::Repository::Spec->new(
    'directory' => $repo_spec_dir,
);

my $total = 0;

foreach my $category (qw< native perl >) {
    my @packages = $base_path->child($category)->children;
    foreach my $package_path (@packages) {
        my $package_name = $package_path->basename;

        $package_path->visit(
            sub {
                my $path     = shift;
                my $spec     = from_toml( $path->slurp_utf8 );
                my $package  = Pakket::Package->new_from_spec($spec);
                my $filename = $spec_repo->store_package_spec($package);

                $total++;

                print "* Stored ", $package->full_name, " as $filename\n";
            },
            { 'recurse' => 1 },
        );
    }
}

print "* Imported $total files. Done.\n";
