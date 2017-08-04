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

=pod

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 spec_repo

Stores the spec repository, built with the backend using
C<spec_repo_backend>.

=head2 spec_repo_backend

A hashref of backend information populated from the config file.
