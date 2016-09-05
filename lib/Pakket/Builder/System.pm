package Pakket::Builder::System;
# ABSTRACT: Build System Pakket packages

use Moose;
use Log::Any qw< $log >;
use Pakket::Log;
use Pakket::Builder::System::Makefile;

with qw<Pakket::Role::Builder>;

sub build_package {
    my ( $self, $package, $build_dir, $prefix, $flags ) = @_;

    if (   $build_dir->child('configure')->exists
        || $build_dir->child('config')->exists )
    {
        my $builder = Pakket::Builder::System::Makefile->new();
        $builder->build_package( $package, $build_dir, $prefix, $flags );
    } else {
        $log->critical("I cannot build this system package. No 'configure'.");
        exit 1;
    }

    return;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=pod
