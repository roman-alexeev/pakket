package Pakket::Web::App;
# ABSTRACT: The Pakket web application

use Dancer2 0.204001 'appname' => 'Pakket::Web'; # decode_json
use Log::Any qw< $log >;
use List::Util qw< first >;
use Path::Tiny ();
use Pakket::Web::Repo;
use constant {
    'PATHS' => [
        $ENV{'PAKKET_WEB_CONFIG'},
        '~/.pakket-web.json',
        '/etc/pakket-web.json',
    ],
};

sub setup {
    my ( $class, $config_file ) = @_;

    $config_file //= first { Path::Tiny::path($_)->exists } @{ PATHS() }
        or die $log->fatal(
            'Please specify a config file: PAKKET_WEB_CONFIG, '
          . '~/.pakket-web.json, or /etc/pakket-web.json.',
        );

    my $config = decode_json( Path::Tiny::path($config_file)->slurp_utf8 );

    foreach my $repo_config ( @{ $config->{'repositories'} } ) {
        Pakket::Web::Repo->create($repo_config);
    }
}

1;

__END__
