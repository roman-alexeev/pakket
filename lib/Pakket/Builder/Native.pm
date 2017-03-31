package Pakket::Builder::Native;
# ABSTRACT: Build Native Pakket packages

use Moose;
use MooseX::StrictConstructor;
use Carp qw< croak >;
use Log::Any qw< $log >;
use Pakket::Log;
use Pakket::Builder::Native::Makefile;

with qw<Pakket::Role::Builder>;

sub build_package {
    my ( $self, $package, $build_dir, $prefix, $flags ) = @_;

    if (   $build_dir->child('configure')->exists
        || $build_dir->child('config')->exists )
    {
        my $builder = Pakket::Builder::Native::Makefile->new();
        $builder->build_package( $package, $build_dir, $prefix, $flags );
    } else {
        croak( $log->critical(
            "I cannot build this native package. No 'configure'.") );
    }

    return;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=pod
