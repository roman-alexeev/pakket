package Pakket::Server::App;
# ABSTRACT: Webapp endpoints to server Pakket information

use Dancer2;
use Log::Any qw< $log >;
use Pakket::Repository::Backend::File;

set 'serializer' => 'JSON';

my $backend;
sub setup {
    my ( $class, $config ) = @_;
    $backend = Pakket::Repository::Backend::File->new(
        'directory' => $config->{'data_dir'},
    );
}

get '/all_object_ids' => sub {
    $log->debug('all_object_ids');

    return {
        'status' => 'OK',
        'data'   => $backend->all_object_ids(),
    };
};

get '/retrieve/:id' => sub {
    my $id = route_parameters->get('id');
    $log->debugf('retrieve [%s]', $id);

    return {
        'status' => 'OK',
        'data'   => $backend->retrieve_content($id),
    };
};

post '/store/:id' => sub {
    my $id = route_parameters->get('id');
    $log->debugf('store [%s]', $id);
    $backend->store_content( $id, body_parameters->get('data') );
    return { 'status' => 'OK' };
};

1;

__END__
