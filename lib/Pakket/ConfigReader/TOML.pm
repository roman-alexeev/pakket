package Pakket::ConfigReader::TOML;
# ABSTRACT: A TOML config reader

use Moose;
use TOML::Parser;
use Types::Path::Tiny qw< Path >;

with qw< Pakket::Role::ConfigReader >;

has filename => (
	is       => 'ro',
	isa      => Path,
    coerce   => 1,
	required => 1,
);

sub read_config {
	my $self        = shift;
	my $config_file = $self->filename;
    -r $config_file
		or die "Config file '$config_file' does not exist or unreadable";

	my $config;
    eval {
        $config = TOML::Parser->new( strict_mode => 1 )
                              ->parse_file($config_file);
        1;
    } or do {
        my $err = $@ || 'Unknown error';
        die "Cannot read $config_file: $err";
    };

    return $config;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;
