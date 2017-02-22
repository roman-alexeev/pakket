package Pakket::Server::App;
# ABSTRACT: Webapp endpoints to server Pakket information

use Dancer2;
use Dancer2::Plugin::Pakket::ParamTypes;

use Log::Any qw< $log >;
use Pakket::Repository::Spec;
use Pakket::Repository::Parcel;
use Pakket::Repository::Source;

## no critic qw(Modules::RequireExplicitInclusion)

# Example
set 'repositories' => {
    'Spec' => [
        'File' => { 'directory' => '/opt/pakket/specs' },
    ],

    'Source' => [
        'File' => { 'directory' => '/opt/pakket/sources' },
    ],

    'Parcel' => [
        'File' => { 'directory' => '/opt/pakket/parcels' },
    ],
};

sub setup {
    my $class = shift;

    my $repositories_data = config()->{'repositories'};
    foreach my $repository_type ( keys %{$repositories_data} ) {
        my $repo_class = "Pakket::Repository::$repository_type";
        my $repo       = $repo_class->new(
            'backend' => $repositories_data->{$repository_type},
        );

        my $prefix = lc $repository_type;

        prefix "/$prefix" => sub {
            get '/has_object' => with_types [
                [ 'query', 'id', 'Str', 'MissingID' ],
            ] => sub {
                my $id = query_parameters->get('id');

                return encode_json({
                    'has_object' => $repo->has_object($id),
                });
            };

            get '/all_object_ids' => sub {
                return encode_json({
                    'object_ids' => $repo->all_object_ids,
                });
            };

            prefix '/retrieve' => sub {
                get '/content' => with_types [
                    [ 'query', 'id', 'Str', 'MissingID' ],
                ] => sub {
                    my $id = query_parameters->get('id');

                    return encode_json( {
                        'id'      => $id,
                        'content' => $repo->retrieve_content($id),
                    } );
                };

                get '/location' => with_types [
                    [ 'query', 'id', 'Str', 'MissingID' ],
                ] => sub {
                    my $id   = query_parameters->get('id');
                    my $file = $repo->retrieve_location($id);

                    # This is already anchored to the repo
                    # (And no user input can change the path it will reach)
                    send_file( $file, 'system_path' => 1 );
                };
            };

            prefix '/store' => sub {
                post '/content' => with_types [
                    [ 'body', 'id',      'Str',  'MissingID'      ],
                    [ 'body', 'content', 'Str', 'MissingContent' ],
                ] => sub {
                    my $id      = body_parameters->get('id');
                    my $content = body_parameters->get('content');
                    return $repo->store_content( $id, $content );
                };

                post '/location' => with_types [
                    [ 'body', 'id',       'Str',  'MissingID'       ],
                    [ 'body', 'filename', 'Str', 'MissingFilename' ],
                ] => sub {
                    my $id       = body_parameters->get('id');
                    my $filename = upload('filename')->tempname;
                    return $repo->store_location( $id, $filename );
                };
            };
        };
    }
}

1;

__END__
