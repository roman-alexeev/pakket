package Pakket::Versioning::Perl;
# ABSTRACT: A Perl-style versioning class

use Moose;
use MooseX::StrictConstructor;
use version 0.77;

with qw< Pakket::Role::Versioning >;

sub compare {
    return version->parse( $_[1] ) <=> version->parse( $_[2] );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
