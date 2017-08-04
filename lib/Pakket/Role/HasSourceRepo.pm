package Pakket::Role::HasSourceRepo;
# ABSTRACT: Provide source repo support

use Moose::Role;
use Pakket::Repository::Source;

has 'source_repo' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Repository::Source',
    'lazy'    => 1,
    'default' => sub {
        my $self = shift;

        return Pakket::Repository::Source->new(
            'backend' => $self->source_repo_backend,
        );
    },
);

has 'source_repo_backend' => (
    'is'      => 'ro',
    'isa'     => 'PakketRepositoryBackend',
    'lazy'    => 1,
    'coerce'  => 1,
    'default' => sub {
        my $self = shift;
        return $self->config->{'repositories'}{'source'};
    },
);

no Moose::Role;

1;

__END__

=pod

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 source_repo

Stores the source repository, built with the backend using
C<source_repo_backend>.

=head2 source_repo_backend

A hashref of backend information populated from the config file.
