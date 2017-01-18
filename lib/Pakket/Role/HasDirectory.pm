package Pakket::Role::HasDirectory;
# ABSTRACT: A role to provide a directory attribute

use Moose::Role;
use Types::Path::Tiny qw< Path >;

has 'directory' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

no Moose::Role;

1;

__END__

=pod

