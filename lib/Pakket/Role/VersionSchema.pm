package Pakket::Role::VersionSchema;

use Moose::Role;

requires 'sort_candidates', 'accepts', 'add_exact', 'add_from_string';

no Moose::Role;

1;
