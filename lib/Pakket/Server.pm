package Pakket::Server;
# ABSTRACT: Start a Pakket server

use Moose;
use MooseX::StrictConstructor;

use Log::Any          qw< $log >;
use Types::Path::Tiny qw< Path >;
use Plack::Runner;

use Pakket::Server::App;

has 'port' => (
    'is'        => 'ro',
    'isa'       => 'Int',
    'predicate' => 'has_port',
);

sub run {
    my $self = shift;

    Pakket::Server::App->setup();
    my $app    = Pakket::Server::App->to_app;
    my $runner = Plack::Runner->new();

    my @runner_opts = (
        $self->has_port ? ( '--port', $self->port ) : (),
    );

    $runner->parse_options(@runner_opts);
    return $runner->run($app);
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__
