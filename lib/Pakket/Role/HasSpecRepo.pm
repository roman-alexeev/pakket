package Pakket::Role::HasSpecRepo;
# ABSTRACT: Provide spec repo support

use Moose::Role;
use Pakket::Repository::Spec;

has 'spec_repo' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Repository::Spec',
    'lazy'    => 1,
    'default' => sub {
        my $self = shift;

        return Pakket::Repository::Spec->new(
            'backend' => $self->spec_repo_backend,
        );
    },
);

has 'spec_repo_backend' => (
    'is'      => 'ro',
    'isa'     => 'PakketRepositoryBackend',
    'lazy'    => 1,
    'coerce'  => 1,
    'default' => sub {
        my $self = shift;
        return $self->config->{'repositories'}{'spec'};
    },
);

no Moose::Role;
1;
__END__
