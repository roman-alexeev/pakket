package Pakket::Log;
# ABSTRACT: A logger for Pakket

use strict;
use warnings;
use parent 'Log::Contextual';
use Log::Dispatch;
use Path::Tiny qw< path >;

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

sub build_logger {
    my ( $class, $verbose ) = @_;
    my $logger = Log::Dispatch->new(
        outputs => [
            $class->_build_logger(),
            $class->_cli_logger( $verbose // 1 ),
        ],
    );

    return $logger;
}

sub _build_logger {
    [
        'File',
        min_level => 'debug',
        filename  => path( Path::Tiny->cwd, 'build.log' )->stringify,
        newline   => 1,
    ];
}

sub cli_logger {
    my ( $class, $verbose ) = @_;
    $verbose ||= 0;

    my $screen_level =
        $verbose >= 3 ? 'debug'  : # log 2
        $verbose == 2 ? 'info'   : # log 1
        $verbose == 1 ? 'notice' : # log 0
                        'warning';

    my $logger = Log::Dispatch->new(
        outputs => [ $class->_cli_logger($screen_level) ],
    );

    return $logger;
}

sub _cli_logger {
    my ( $class, $screen_level ) = @_;

    return [
        'Screen',
        min_level => $screen_level,
        newline   => 1,
    ];
}

sub arg_levels {
    [qw< debug info notice warning error critical alert emergency >];
}

sub default_import { ':log' }

1;

__END__
