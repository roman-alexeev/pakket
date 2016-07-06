#!/usr/bin/perl
use strict;
use warnings;

use JSON;
use Path::Tiny;
use Getopt::Long::Descriptive;
use version;

my ( $opt, $usage ) = describe_options(
    "$0 %o",
    [ 'config-dir=s', 'Configuration directory', { required => 1 } ],
    [ 'sources-dir=s', 'Sources directory', { default => 'sources/' } ],
    [ 'output-file=s', 'Output file',       { default => 'pkg_index.json' } ],
    [],
    [ 'help', 'Usage' ],
);

$opt->help
    and print $usage->text
    and exit;

my $output = path( $opt->output_file );

$output->exists
    and die "$output already exists";

my $index = {};

my $category_iter = path( $opt->config_dir )->iterator;
while ( my $category = $category_iter->() ) {
    $category->is_dir and "$category" ne '.'
        or return;

    my $category_name = $category->basename;
    my $dist_iter     = $category->iterator;
    while ( my $dist = $dist_iter->() ) {
        my @versions = map s{.+/([^/]+)\.toml$}{$1}r,
            $dist->children(qr/\.toml$/);

        my ($latest_version)
            = sort { version->parse($b) <=> version->parse($a) } @versions;

        $index->{$category_name}{ $dist->basename } = {
            latest => $latest_version,
            versions =>
                { map +( $_ => $dist->basename . "-$_" ), @versions, },
        };

    }
}

$output->spew_utf8( JSON->new->pretty->encode($index) );
