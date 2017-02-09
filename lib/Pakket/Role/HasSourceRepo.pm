package Pakket::Role::HasSourceRepo;
# ABSTRACT: Provide source repo support

use Moose::Role;
use Types::Path::Tiny qw< Path >;

use Pakket::Repository::Source;

has 'source_dir' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

has 'source_repo' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Repository::Source',
    'lazy'    => 1,
    'builder' => '_build_source_repo',
);

# We're starting with a local repo
# # but in the future this will be dictated from a configuration
sub _build_source_repo {
    my $self = shift;

    # Use default for now, but use the directory we want at least
    return Pakket::Repository::Source->new(
        'directory' => $self->source_dir,
    );
}

1;
no Moose::Role;
__END__
