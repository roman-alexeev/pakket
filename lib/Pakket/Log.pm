package Pakket::Log;
# ABSTRACT: A logger for Pakket

use strict;
use warnings;
use Log::Dispatch;
use Path::Tiny qw< path >;

use constant {
    'DEBUG_LOG_LEVEL'    => 3,
    'DEBUG_INFO_LEVEL'   => 2,
    'DEBUG_NOTICE_LEVEL' => 1,
};

# Just so I remember it:
# 1  fatal     system unusable, aborts program!
# 2  alert     failure in primary system
# 3  critical  failure in backup system
# 4  error     non-urgent program errors, a bug
# 5  warning   possible problem, not necessarily error
# 6  notice    unusual conditions
# 7  info      normal messages, no action required
# 8  debug     debugging messages for development
# 9  trace     copious tracing output

sub arg_default_logger {
    return $_[1] || Log::Dispatch->new(
        'outputs' => [
            [
                'Screen',
                'min_level' => 'notice',
                'newline'   => 1,
            ],
        ],
    );
}

sub build_logger {
    my ( $class, $verbose ) = @_;
    my $logger = Log::Dispatch->new(
        'outputs' => [
            $class->_build_logger(),
            $class->_cli_logger( $verbose // 1 ),
        ],
    );

    return $logger;
}

sub _build_logger {
    return [
        'File',
        'min_level' => 'debug',
        'filename'  => path( Path::Tiny->cwd, 'build.log' )->stringify,
        'newline'   => 1,
    ];
}

sub cli_logger {
    my ( $class, $verbose ) = @_;

    my $logger = Log::Dispatch->new(
        'outputs' => [ $class->_cli_logger($verbose) ],
    );

    return $logger;
}

sub _cli_logger {
    my ( $class, $verbose ) = @_;

    $verbose ||= 0;

    my $screen_level =
        $verbose >= +DEBUG_LOG_LEVEL    ? 'debug'  : # log 2
        $verbose == +DEBUG_INFO_LEVEL   ? 'info'   : # log 1
        $verbose == +DEBUG_NOTICE_LEVEL ? 'notice' : # log 0
                                          'warning';
    return [
        'Screen::Gentoo',
        'min_level' => $screen_level,
        'newline'   => 1,
        'utf8'      => 1,
    ];
}

1;

__END__
