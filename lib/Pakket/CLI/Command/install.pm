package Pakket::CLI::Command::install;
# ABSTRACT: The pakket install command

use strict;
use warnings;
use Pakket::CLI '-command';
use Pakket::Installer;
use Pakket::Log;
use Log::Any::Adapter;
use Path::Tiny      qw< path >;

sub abstract    { 'Install a package' }
sub description { 'Install a package' }

sub opt_spec {
    return (
        [ 'to=s',       'directory to install the package in'  ],
        [ 'verbose|v+', 'verbose output (can be provided multiple times)' ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    my $logger = Pakket::Log->cli_logger(2); # verbosity
    Log::Any::Adapter->set( 'Dispatch', dispatcher => $logger );

    defined $opt->{'to'}
        and $self->{'installer'}{'library_dir'} = $opt->{'to'};

    @{$args} == 0
        and $self->usage_error('Must provide parcels to install');

    my @parcels = @{$args};

    # FIXME: support more options here :)
    # (validation for URLs, at least for now)
    foreach my $parcel (@parcels) {
        -f $parcel
            or $self->usage_error('Currently only a parcel file is supported');
    }

    $self->{'parcel_files'} = \@parcels;
}

sub execute {
    my $self      = shift;
    my $installer = Pakket::Installer->new(
        map( +(
            defined $self->{'installer'}{$_}
                ? ( $_ => $self->{'installer'}{$_} )
                : ()
        ), qw< library_dir > ),
    );

    return $installer->install( @{ $self->{'parcel_files'} } );
}

1;

__END__
