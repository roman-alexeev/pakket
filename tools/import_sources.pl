#!/usr/bin/perl

use strict;
use warnings;
use Pakket::Package;
use Pakket::Repository::Source;
use Path::Tiny qw< path >;
use Log::Any::Adapter;
use Log::Dispatch;
use JSON::MaybeXS qw< decode_json >;

Log::Any::Adapter->set(
    'Dispatch',
    'dispatcher' => Log::Dispatch->new(
        'outputs' => [ [ 'Screen', 'min_level' => 'debug', 'newline' => 1 ], ],
    ),
);

my ( $index_file, $prev_source_dir, $repo_source_dir ) = @ARGV;
$index_file && $prev_source_dir && $repo_source_dir
    or die "$0 <index.json> <source dir> <repo source dir>\n";

my $source_repo = Pakket::Repository::Source->new(
    'directory' => $repo_source_dir,
);

my $index = JSON::MaybeXS::decode_json( path($index_file)->slurp_utf8 );

my $total = 0;

foreach my $category ( keys %{$index} ) {
    foreach my $package_name ( keys %{ $index->{$category} } ) {
        my $version        = $index->{$category}{$package_name}{'latest'};
        my $source_basedir
            = $index->{$category}{$package_name}{'versions'}{$version};

        my $source_dir = path($prev_source_dir)->child($source_basedir);
        if ( !$source_dir->exists || !$source_dir->is_dir ) {
            next;
            #die "$source_dir does not exist. Panicking!\n";
        }

        my $package = Pakket::Package->new(
            'category' => $category,
            'name'     => $package_name,
            'version'  => $version,
        );

        $source_repo->store_package_source(
            $package, $source_dir,
        );

        $total++;
    }
}

print "* Imported $total files. Done.\n";
