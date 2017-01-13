package Pakket::Requirement;
# ABSTRACT: A Pakket requirement

use Moose;
use MooseX::StrictConstructor;

with qw< Pakket::Role::PrintableNames >;

has [qw< category name version >] => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

no Moose;
__PACKAGE__->meta->make_immutable;

1;
