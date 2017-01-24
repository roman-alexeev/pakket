package Pakket::CLI::Command::serve;
# ABSTRACT: Serve Pakket objects over HTTP

use strict;
use warnings;

use Path::Tiny      qw< path >;
use Log::Any::Adapter;

use Pakket::CLI '-command';
use Pakket::Server;
use Pakket::Log;

sub abstract    { 'Serve objects' }
sub description { 'Serve objects' }

sub opt_spec {
    return (
        [ 'port=s',     'port where server will listen', ],
        [ 'data-dir=s', 'location of local files', { 'required' => 1 } ],
        [ 'verbose|v+', 'verbose output (can be provided multiple times)' ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    my $data_dir = path( $opt->{'data_dir'} );
    $data_dir->exists && $data_dir->is_dir
        or $self->usage_error("Incorrect data directory specified: '$data_dir'");

    $self->{'server'}{'data_dir'} = $data_dir;

    $self->{'server'}{$_} = $opt->{$_} for qw< port >;

    Log::Any::Adapter->set( 'Dispatch',
        'dispatcher' => Pakket::Log->build_logger( $opt->{'verbose'} ) );
}

sub execute {
    my $self   = shift;
    my $server = Pakket::Server->new(
        # default main object
        map( +(
            defined $self->{'server'}{$_}
                ? ( $_ => $self->{'server'}{$_} )
                : ()
        ), qw< data_dir port > ),
    );

    $server->run();
}

1;

__END__
