package Pakket::Log;
# ABSTRACT: A logger for Pakket

use strict;
use warnings;
use parent 'Log::Contextual';
use Log::Dispatch;

sub arg_default_logger {
    $_[1] || Log::Dispatch->new(
        outputs => [
            [
                'Screen',
                min_level => 'notice',
                newline   => 1,
            ],
        ],
    );
}

sub arg_levels {
    [qw< debug info notice warning error critical alert emergency >];
}

sub default_import { ':log' }

1;

__END__
