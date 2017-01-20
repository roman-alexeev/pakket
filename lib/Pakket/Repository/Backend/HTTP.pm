package Pakket::Repository::Backend::HTTP;
# ABSTRACT: A remote HTTP backend repository

use Moose;
use MooseX::StrictConstructor;

use JSON::MaybeXS     qw< encode_json decode_json >;
use Path::Tiny        qw< path >;
use HTTP::Tiny;
use Log::Any          qw< $log >;
use Types::Path::Tiny qw< Path >;

with qw<
    Pakket::Role::Repository::Backend
>;

has 'host' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'port' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'base_url' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'lazy'     => 1,
    'builder'  => '_build_base_url',
);

has 'http_client' => (
    'is'       => 'ro',
    'isa'      => 'HTTP::Tiny',
    'default'  => sub { HTTP::Tiny->new },
);

sub _build_base_url {
    my $self = shift;
    sprintf('http://%s:%s', $self->host, $self->port);
}

sub all_object_ids {
    my $self     = shift;
    my $url      = '/all_object_ids';
    my $full_url = $self->base_url . $url;
    my $response = $self->http_client->get($full_url);
    if (!$response->{success}) {
        $log->criticalf('Could not get remote all_object_ids: %d -- %s',
                        $response->{status}, $response->{reason});
        exit 1;
    }
    my $content = decode_json($response->{content});
    return $content->{data};
}

sub store_location {
    my ( $self, $id, $file_to_store ) = @_;
    my $content = {
        data => path($file_to_store)->slurp( { 'binmode' => ':raw' } ),
    };
    $self->store_content( $id, $content );
}

sub retrieve_location {
    my ( $self, $id ) = @_;
    my $content = $self->retrieve_content->($id);
    my $location = Path::Tiny->tempfile;
    $location->spew( { 'binmode' => ':raw' }, $content );
    return $location;
}

sub store_content {
    my ( $self, $id, $content ) = @_;
    my $url      = "/store/$id";
    my $full_url = $self->base_url . $url;
    my $response = $self->http_client->post(
        $full_url => {
            content => encode_json({ data => $content }),
            headers => {
                "Content-Type" => "application/json",
            },
        },
    );
    if (!$response->{success}) {
        $log->criticalf('Could not store content for id %s', $id);
        exit 1;
    }
}

sub retrieve_content {
    my ( $self, $id ) = @_;
    my $url      = "/retrieve/$id";
    my $full_url = $self->base_url . $url;
    my $response = $self->http_client->get($full_url);
    if (!$response->{success}) {
        $log->criticalf('Could not retrieve content for id %s', $id);
        exit 1;
    }
    my $content = decode_json($response->{content});
    return $content->{data};
}


__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod
