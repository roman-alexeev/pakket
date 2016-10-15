package Pakket::ConfigReader;
# ABSTRACT: The Pakket config reader

use Moose;
use Module::Runtime qw< use_module >;

has 'type' => (
	'is'       => 'ro',
	'isa'      => 'Str',
	'required' => 1,
);

has 'args' => (
	'is'      => 'ro',
	'isa'     => 'ArrayRef',
	'default' => sub { +[] },
);

has 'config_object' => (
	'is'      => 'ro',
    'does'    => 'Pakket::Role::ConfigReader',
	'lazy'    => 1,
	'builder' => '_build_config_object',
);

sub _build_config_object {
	my $self    = shift;
	my $type    = $self->type;
	my $package = "Pakket::ConfigReader::$type";

	return use_module($package)->new( @{ $self->args } );
}

sub read_config {
	my ( $self, @args ) = @_;
	my $config = $self->config_object->read_config(@args);
	return $config;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;
