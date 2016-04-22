package Pakket::Role::Log;
# ABSTRACT: A logging ability for Pakket objects

use Moose::Role;
use Log::Contextual qw< :log with_logger set_logger >;
use Log::Dispatch;
use Path::Tiny;
use Types::Path::Tiny qw< Path >;

has verbose => (
    is      => 'ro',
    isa     => 'Int',
    default => sub {0},
);

has logger => (
    is      => 'ro',
    isa     => 'Object',
    lazy    => 1,
    builder => '_build_logger',
);

has log_file => (
    is      => 'ro',
    isa     => Path,
    default => sub { path( Path::Tiny->cwd, 'build.log' ) },
);

sub _build_logger {
    my $self = shift;

    my $screen_level =
        $self->verbose >= 3 ? 'debug'  : # log 2
        $self->verbose == 2 ? 'info'   : # log 1
        $self->verbose == 1 ? 'notice' : # log 0
                              'warning';

    my $logger = Log::Dispatch->new(
        outputs => [
            [
                'File',
                min_level => 'debug',
                filename  => $self->log_file->stringify,
                newline   => 1,
            ],

            [
                'Screen',
                min_level => $screen_level,
                newline   => 1,
            ],
        ],
    );

    return $logger;
}

sub BUILD {
    my $self = shift;
    my $logger = $self->logger;
    $self->can('set_logger')->($logger);
}

1;

__END__
