package Pakket::Role::BasicPackageAttrs;
# ABSTRACT: Some helpers to print names nicely

use Moose::Role;
use Pakket::Utils qw< canonical_package_name >;

sub short_name {
    my $self = shift;
    return canonical_package_name( $self->category, $self->name );
}

sub full_name {
    my $self = shift;
    return canonical_package_name(
        $self->category, $self->name, $self->version,
    );
}

no Moose::Role;

1;

__END__

=pod
