use strict;
use warnings;

use Test::More;
use Pakket::VersionFilter;

exit main();

sub main {
    my %filters = (
        " >= 2.0, != 2.2" => {
            parsed => [
                [ '>=', '2.0' ],
                [ '!=', '2.2' ],
            ],
            available => [ '1.8', '1.9', '2.0', '2.0.5', '2.1', '2.1.9', '2.2', '2.2.1', '2.5', '3.0', ],
            filtered =>  [ '2.0', '2.0.5', '2.1', '2.1.9', '2.2.1', '2.5', '3.0', ],
        },
        ">1.0, < 2.0 " => {
            parsed => [
                [ '>', '1.0' ],
                [ '<', '2.0' ],
            ],
            available => [ '1.0', '1.5', '1.9', '2.0', '2.1', ],
            filtered =>  [ '1.5', '1.9', ],
        },
    );

    foreach my $filter (keys %filters) {
        my $version_filter = Pakket::VersionFilter->new(
            filter_string => $filter,
        );
        my $spec = $version_filter->filters;
        my $parsed = $filters{$filter}{parsed};
        is_deeply($spec, $parsed,
                  "properly parsed '$filter' => [" . join(",", map +( join(":", @$_), @$spec)) . "]");

        my $available = $filters{$filter}{available};
        my $filtered = $filters{$filter}{filtered};
        my $usable = $version_filter->filter_versions($available);
        is_deeply($usable, $filtered,
                  "properly filtered '$filter' => [" . join(",", @$filtered) . "]");
    }

    done_testing;
    return 0;
}
