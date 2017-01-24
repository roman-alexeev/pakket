package Pakket::Role::HasDirectory;
# ABSTRACT: A role to provide a directory attribute

use Moose::Role;
use Types::Path::Tiny qw< AbsPath >;

has 'directory' => (
    'is'       => 'ro',
    'isa'      => AbsPath,
    'coerce'   => 1,
    'required' => 1,
);

no Moose::Role;

1;

__END__

=pod

