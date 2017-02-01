#!/usr/bin/perl
use strict;
use warnings;

use Path::Tiny;
use Getopt::Long::Descriptive;
use version;

use Pakket::Utils qw< generate_json_conf >;

my ( $opt, $usage ) = describe_options(
    "$0 %o",
    [ 'spec-dir=s',    'Spec directory', { required => 1 } ],
    [ 'output-file=s', 'Output file',    { default => 'pkg_index.json' } ],
    [],
    [ 'help', 'Usage' ],
);

$opt->help
    and print $usage->text
    and exit;

generate_json_conf( $opt->output_file, $opt->spec_dir );

1;
