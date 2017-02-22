package Pakket::CLI::Command::install;
# ABSTRACT: The pakket install command

use strict;
use warnings;
use Pakket::CLI '-command';
use Pakket::Installer;
use Pakket::Log;
use Pakket::Package;
use Pakket::Constants qw< PAKKET_PACKAGE_SPEC >;
use Log::Any::Adapter;
use Path::Tiny      qw< path >;

sub abstract    { 'Install a package' }
sub description { 'Install a package' }

sub opt_spec {
    return (
        [
            'to=s',
            'directory to install the package in',
            { 'required' => 1 },
        ],
        [
            'from=s',
            'directory to install the packages from',
            { 'required' => 1 },
        ],
        [ 'input-file=s', 'install eveything listed in this file' ],
        [
            'verbose|v+',
            'verbose output (can be provided multiple times)',
            { 'default' => 1 },
        ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    Log::Any::Adapter->set( 'Dispatch',
        'dispatcher' => Pakket::Log->build_logger( $opt->{'verbose'} ) );

    $self->{'installer'}{'pakket_dir'} = $opt->{'to'};
    $self->{'installer'}{'parcel_dir'} = $opt->{'from'};

    my @package_strs
        = defined $opt->{'input_file'}
        ? path( $opt->{'input_file'} )->lines_utf8( { 'chomp' => 1 } )
        : @{$args};

    my @packages;
    foreach my $package_str (@package_strs) {
        my ( $pkg_cat, $pkg_name, $pkg_version ) =
            $package_str =~ PAKKET_PACKAGE_SPEC();

        if ( !defined $pkg_version ) {
            $self->usage_error(
                'Currently you must provide a version to install: '
                .  $package_str,
            );
        }

        push @packages, Pakket::Package->new(
            'category' => $pkg_cat,
            'name'     => $pkg_name,
            'version'  => $pkg_version,
        );
    }

    $self->{'packages'} = \@packages;
}

sub execute {
    my $self      = shift;
    my $installer = Pakket::Installer->new(
        map( +(
            defined $self->{'installer'}{$_}
                ? ( $_ => $self->{'installer'}{$_} )
                : ()
        ), qw< pakket_dir parcel_dir > ),
    );

    return $installer->install( @{ $self->{'packages'} } );
}

1;

__END__
