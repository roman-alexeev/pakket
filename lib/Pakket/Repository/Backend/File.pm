package Pakket::Repository::Backend::File;
# ABSTRACT: A file-based backend repository

use Moose;
use MooseX::StrictConstructor;

use JSON::MaybeXS     qw< encode_json decode_json >;
use Path::Tiny        qw< path >;
use Log::Any          qw< $log >;
use Types::Path::Tiny qw< Path >;
use Digest::SHA       qw< sha1_hex >;

with qw<
    Pakket::Role::HasDirectory
    Pakket::Role::Repository::Backend
>;

has 'file_extension' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => sub {'sgm'},
);

has 'index_file' => (
    'is'       => 'ro',
    'isa'      => Path,
    'coerce'   => 1,
    'default'  => sub {
        my $self = shift;
        return $self->directory->child('index.json');
    },
);

has 'repo_index' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'builder' => '_build_repo_index',
);

sub _build_repo_index {
    my $self = shift;
    my $file = $self->index_file;

    $file->is_file
        or return +{};

    return decode_json( $file->slurp_utf8 );
}

sub all_object_ids {
    my $self           = shift;
    my @all_object_ids = keys %{ $self->repo_index };
    return \@all_object_ids;
}

sub _store_in_index {
    my ( $self, $id ) = @_;

    # Decide on a proper filename for $id
    # Meaningless extension
    my $filename = sha1_hex($id) . '.' . $self->file_extension;

    # Store in the index
    $self->repo_index->{$id} = $filename;
    $self->index_file->spew_utf8( encode_json( $self->repo_index ) );

    return $filename;
}

sub _retrieve_from_index {
    my ( $self, $id ) = @_;
    return $self->repo_index->{$id};
}

sub _remove_from_index {
    my ( $self, $id ) = @_;
    return delete $self->repo_index->{$id};
}

sub store_location {
    my ( $self, $id, $file_to_store ) = @_;
    my $filename  = $self->_store_in_index($id);
    my $directory = $self->directory;

    return path($file_to_store)->copy( $directory->child($filename) );
}

sub retrieve_location {
    my ( $self, $id ) = @_;
    my $filename = $self->_retrieve_from_index($id);
    $filename
        and return $self->directory->child($filename);

    $log->debug("File for ID '$id' does not exist in storage");
    return;
}

sub remove_location {
    my ( $self, $id ) = @_;
    $self->retrieve_location($id)->unlink;
    $self->_remove_from_index($id);
    return 1;
}

sub store_content {
    my ( $self, $id, $content ) = @_;
    my $file_to_store = Path::Tiny->tempfile;
    $file_to_store->spew( { 'binmode' => ':raw' }, $content );
    return $self->store_location( $id, $file_to_store );
}

sub retrieve_content {
    my ( $self, $id ) = @_;
    return $self->retrieve_location($id)
                ->slurp( { 'binmode' => ':raw' } );
}

sub remove_content {
    my ( $self, $id ) = @_;
    return $self->remove_location($id);
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod
