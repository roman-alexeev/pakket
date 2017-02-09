package Pakket::Role::HasParcelRepo;
# ABSTRACT: Provide parcel repo support

use Moose::Role;
use Types::Path::Tiny qw< Path >;

use Pakket::Repository::Parcel;

has 'parcel_dir' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'required' => 1,
);

has 'parcel_repo' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Repository::Parcel',
    'lazy'    => 1,
    'builder' => '_build_parcel_repo',
);

# We're starting with a local repo
# # but in the future this will be dictated from a configuration
sub _build_parcel_repo {
    my $self = shift;

    # Use default for now, but use the directory we want at least
    return Pakket::Repository::Parcel->new(
        'directory' => $self->parcel_dir,
    );
}

1;
no Moose::Role;
__END__
