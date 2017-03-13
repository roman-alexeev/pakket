package Pakket::Role::Versioning;
# ABSTRACT: A Versioning role

use Moose::Role;

requires qw< compare >;

no Moose::Role;
1;
