package Pakket::Role::HasSpecRepo;
# ABSTRACT: Provide spec repo support

use Moose::Role;
use Types::Path::Tiny qw< Path >;

use Pakket::Repository::Spec;

has 'spec_dir' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

has 'spec_repo' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Repository::Spec',
    'lazy'    => 1,
    'builder' => '_build_spec_repo',
);

# We're starting with a local repo
# # but in the future this will be dictated from a configuration
sub _build_spec_repo {
    my $self = shift;

    # Use default for now, but use the directory we want at least
    return Pakket::Repository::Spec->new(
        'directory' => $self->spec_dir,
    );
}

1;
no Moose::Role;
__END__
