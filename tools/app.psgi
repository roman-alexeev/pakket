use strict;
use warnings;
use Path::Tiny    qw< path >;
use JSON::MaybeXS qw< decode_json >;

use Pakket::Serve::App;

my $config_file = path('pakket-config.json');
my $config
    = $config_file->exists ? decode_json( $config_file->slurp_utf8 ) : {};

Pakket::Server::App->setup($config);
Pakket::Server::App->to_app;
