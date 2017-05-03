package Pakket::CLI::Command::serve;
# ABSTRACT: Serve Pakket objects over HTTP

use strict;
use warnings;

use Path::Tiny      qw< path >;
use Log::Any::Adapter;

use Pakket::CLI '-command';
use Pakket::Web::Server;
use Pakket::Log;

sub abstract    { 'Serve objects' }
sub description { 'Serve objects' }

sub opt_spec {
    return (
        [ 'port=s',     'port where server will listen', ],
        [ 'verbose|v+', 'verbose output (can be provided multiple times)' ],
    );
}

sub validate_args {
    my ( $self, $opt ) = @_;

    Log::Any::Adapter->set( 'Dispatch',
        'dispatcher' => Pakket::Log->build_logger( $opt->{'verbose'} ) );
}

sub execute {
    my ( $self, $opt ) = @_;
    my $server = Pakket::Web::Server->new(
        # default main object
        map( +(
            defined $opt->{$_}
                ? ( $_ => $opt->{$_} )
                : ()
        ), qw< port > ),
    );

    $server->run();
}

1;

__END__
