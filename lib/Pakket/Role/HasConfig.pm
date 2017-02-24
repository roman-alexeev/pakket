package Pakket::Role::HasConfig;
# ABSTRACT: A role providing access to the Pakket configuration file

use Moose::Role;
use Pakket::Config;

has 'config' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'lazy'    => 1,
    'builder' => '_build_config',
);

sub _build_config {
    my $self        = shift;
    my $config_reader = Pakket::Config->new();
    return $config_reader->read_config;
}

no Moose::Role;
1;

__END__
