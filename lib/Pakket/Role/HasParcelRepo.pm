package Pakket::Role::HasParcelRepo;
# ABSTRACT: Provide parcel repo support

use Moose::Role;
use Pakket::Repository::Parcel;

has 'parcel_repo' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Repository::Parcel',
    'lazy'    => 1,
    'default' => sub {
        my $self = shift;

        return Pakket::Repository::Parcel->new(
            'backend' => $self->parcel_repo_backend,
        );
    },
);

has 'parcel_repo_backend' => (
    'is'      => 'ro',
    'isa'     => 'PakketRepositoryBackend',
    'lazy'    => 1,
    'coerce'  => 1,
    'default' => sub {
        my $self = shift;
        return $self->config->{'repositories'}{'parcel'};
    },
);

no Moose::Role;

1;

__END__

=pod

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 parcel_repo

Stores the parcel repository, built with the backend using
C<parcel_repo_backend>.

=head2 parcel_repo_backend

A hashref of backend information populated from the config file.
