package Pakket::Repository;
# ABSTRACT: Build in-memory representation of repo

use Moose;
use MooseX::StrictConstructor;

use Log::Any      qw< $log >;
use Pakket::Types qw< PakketRepositoryBackend >;

has 'backend' => (
    'is'      => 'ro',
    'does'    => 'PakketRepositoryBackend',
    'coerce'  => 1,
    'lazy'    => 1,
    'builder' => '_build_backend',
    'handles' => [ qw<
        all_object_ids
        store_content  retrieve_content
        store_location retrieve_location
    > ],
);

sub _build_backend {
    my $self = shift;
    $log->critical(
        'You did not specify a backend '
      . '(using parameter or builder)',
    );

    exit 1;
}

sub BUILD {
    my $self = shift;
    $self->backend();
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod
