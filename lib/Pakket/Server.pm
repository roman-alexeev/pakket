package Pakket::Server;
# ABSTRACT: Start a Pakket server

use Moose;
use MooseX::StrictConstructor;

use Log::Any          qw< $log >;
use Types::Path::Tiny qw< Path >;
use Pakket::Server::App;

has 'data_dir' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

sub run {
    my $self = shift;

    Pakket::Server::App->setup( { 'data_dir' => $self->data_dir } );
    return Pakket::Server::App->to_app;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__
