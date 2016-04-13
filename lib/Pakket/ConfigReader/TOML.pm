package Pakket::ConfigReader::TOML;

use Moose;
with 'Pakket::Role::ConfigReader';

use TOML::Parser;
use Types::Path::Tiny qw< Path >;

has filename => (
	is       => 'ro',
	isa      => Path,
	required => 1,
);

sub get_config {
	my $self = shift;
	my $config_file;
	$config_file = $self->filename
		or die "Cannot find config file . $config_file";

	my $config;
    eval {
        $config = TOML::Parser->new( strict_mode => 1 )->parse_file($config_file);
        1;
    } or do {
        my $err = $@ || 'Unknown error';
        die "Cannot read $config_file: $err";
    };
    return $config;
}

__PACKAGE__->meta->make_immutable;

1;