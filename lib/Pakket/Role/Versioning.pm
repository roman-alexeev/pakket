package Pakket::Role::Versioning;
# ABSTRACT: A versioning role, for any scheme

use Moose::Role;

has 'versions' => (
    'is'       => 'ro',
    'isa'      => 'ArrayRef',
    'required' => 1,
);

requires qw<
    sort_candidates
    version_from_range
>;


no Moose::Role;

1;
