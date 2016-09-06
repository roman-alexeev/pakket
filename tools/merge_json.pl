use strict;
use warnings;

use Getopt::Long::Descriptive;
use Path::Tiny;
use JSON::MaybeXS qw< decode_json encode_json >;

sub _usage {
    my $msg = shift;

    $msg and print "$msg\n";

    print <<"END_USAGE";
$0 INPUT

INPUT:
$0 --orig FILE --new FILE --output FILE

    orig-file    original JSON file to merge with (read-only)
    new-file     new JSON file to merge from (read-only)
    output-file  output file to write merged contents to

END_USAGE

    exit 1;
}

my ( $opt, $usage ) = describe_options(
    "$0 %o",
    [ 'orig-file=s',   'original JSON file to merge with (read-only)', { required => 1 } ],
    [ 'new-file=s',    'new JSON file to merge from (read-only)', { required => 1 } ],
    [ 'output-file=s', 'output file to write merged contents to', { required => 1 } ],
    [],
    [ 'help', 'Usage' ],
);

$opt->help
    and print $usage->text
    and exit;

my $orig   = decode_json( path( $opt->orig_file )->slurp_utf8 );
my $latest = decode_json( path( $opt->new_file )->slurp_utf8 );
$latest and $orig or _usage("failed to parse JSON files");

for my $cat ( keys %{ $latest } ) {
    if ( exists $orig->{$cat} ) {
        for my $dist ( keys %{ $latest->{$cat} } ) {
            if ( exists $orig->{$cat}{$dist} ) {
                for my $ver ( keys %{ $latest->{$cat}{$dist}{versions} } ) {
                    if ( !exists $orig->{$cat}{$dist}{versions}{$ver} ) {
                        # TODO: add interactive approval check (+ enabling flag)
                        #       cause we don't always want to merge another
                        #       version of the same distribution -- mickey

                        $orig->{$cat}{$dist}{versions}{$ver} =
                            $latest->{$cat}{$dist}{versions}{$ver};
                        print "[ADDED] category:$cat, distribution:$dist, version:$ver\n";
                    }
                }
            }
            else {
                $orig->{$cat}{$dist} = $latest->{$cat}{$dist};
                print "[ADDED] category:$cat, distribution:$dist\n";
            }
        }
    }
    else {
        $orig->{$cat} = $latest->{$cat};
        print "[ADDED] category:$cat\n";
    }
}

my $json = JSON::MaybeXS->new->utf8->pretty(1)->canonical->encode( $orig );
path( $opt->output_file )->spew_utf8($json);

1;
