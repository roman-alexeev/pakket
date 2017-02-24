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
