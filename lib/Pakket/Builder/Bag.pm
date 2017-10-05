package Pakket::Builder::Bag;
# ABSTRACT: Build Bag Pakket packages

use Moose;
use MooseX::StrictConstructor;
use Carp qw< croak >;
use Log::Any qw< $log >;
use Pakket::Log;
use Pakket::Builder::Bag::Makefile;

with qw<Pakket::Role::Builder>;

sub build_package {
    my ( $self, $package, $build_dir, $prefix, $flags ) = @_;

    croak( $log->critical(
        "Cannot build bag package '$package', have not learned yet" ));

    return;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=pod
