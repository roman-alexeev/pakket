package Pakket::Server;
# ABSTRACT: Serve pakket packages

use Moose;
use MooseX::StrictConstructor;

use Types::Path::Tiny         qw< Path >;
use Log::Any                  qw< $log >;

use Pakket::Repository::Backend::File;
use Dancer2;

with 'Pakket::Role::RunCommand';

has 'port' => (
    'is'      => 'ro',
    'isa'     => 'Num',
    'required'  => 1,
);

has 'data_dir' => (
    'is'      => 'ro',
    'isa'     => Path,
    'coerce'  => 1,
    'required'  => 1,
);

has 'backend' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Repository::Backend::File',
    'lazy'  => 1,
    'builder'  => '_build_backend'
);

sub _build_backend {
    my $self = shift;

    # hardcoded to File for now
    return Pakket::Repository::Backend::File->new(
        'directory' => $self->data_dir,
    );
}

sub serve {
    my $self = shift;

    set serializer => 'JSON';
    set port => $self->port;

    my $backend = $self->backend;

    get '/all_object_ids' => sub {
        $log->debug('all_object_ids');
        my $response = {
            status => "OK",
            data => $backend->all_object_ids(),
        };
        return $response;
    };

    get '/retrieve/:id' => sub {
        my $id   = params->{id};
        $log->debugf('retrieve [%s]', $id);
        my $response = {
            status => "OK",
            data => $backend->retrieve_content($id),
        };
        return $response;
    };

    post '/store/:id' => sub {
        my $id   = params->{id};
        $log->debugf('store [%s]', $id);
        my $content = from_json(request->content);
        $backend->store_content($id, $content->{data});
        my $response = {
            status => "OK",
        };
        return $response;
    };

    dance;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__
