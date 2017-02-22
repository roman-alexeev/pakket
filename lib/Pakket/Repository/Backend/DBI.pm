package Pakket::Repository::Backend::DBI;
# ABSTRACT: A DBI-based backend repository

# FIXME: Add methods: remove_location, remove_content

use Moose;
use MooseX::StrictConstructor;

use DBI        qw< :sql_types >;
use Types::DBI;
use Path::Tiny qw< path >;
use Log::Any   qw< $log >;

with qw<
    Pakket::Role::Repository::Backend
>;

has 'dbh' => (
   'is'       => 'ro',
   'isa'      => Dbh,
   'required' => 1,
   'coerce'   => 1,
);

## no critic qw(Variables::ProhibitPackageVars)
sub all_object_ids {
    my $self = shift;
    my $sql  = q{SELECT id FROM data};
    my $stmt = $self->dbh->prepare($sql);

    if ( !$stmt ) {
        $log->criticalf(
            'Could not prepare statement [%s] => %s',
            $sql,
            $DBI::errstr,
        );

        exit 1;
    }

    if ( !$stmt->execute() ) {
        $log->criticalf(
            'Could not get remote all_object_ids: %s',
            $DBI::errstr,
        );

        exit 1;
    }

    my @all_object_ids = map +( $_->[0] ), @{ $stmt->fetchall_arrayref() };
    return \@all_object_ids;
}

sub store_location {
    my ( $self, $id, $file_to_store ) = @_;
    my $content = path($file_to_store)->slurp( { 'binmode' => ':raw' } );
    $self->store_content( $id, $content );
}

sub retrieve_location {
    my ( $self, $id ) = @_;
    my $content = $self->retrieve_content->($id);
    my $location = Path::Tiny->tempfile;
    $location->spew( { 'binmode' => ':raw' }, $content );
    return $location;
}

sub store_content {
    my ( $self, $id, $content ) = @_;
    {
        my $sql  = q{DELETE FROM data WHERE id = ?};
        my $stmt = $self->dbh->prepare($sql);
        if ( !$stmt ) {
            $log->criticalf(
                'Could not prepare statement [%s] => %s',
                $sql,
                $DBI::errstr,
            );

            exit 1;
        }

        $stmt->bind_param( 1, $id, SQL_VARCHAR );
        if ( !$stmt->execute() ) {
            $log->criticalf(
                'Could not delete content for id %d: %s',
                $id,
                $DBI::errstr,
            );

            exit 1;
        }
    }
    {
        my $sql  = q{INSERT INTO data (id, content) VALUES (?, ?)};
        my $stmt = $self->dbh->prepare($sql);
        if ( !$stmt ) {
            $log->criticalf(
                'Could not prepare statement [%s] => %s',
                $sql,
                $DBI::errstr,
            );

            exit 1;
        }

        $stmt->bind_param( 1, $id,      SQL_VARCHAR );
        $stmt->bind_param( 2, $content, SQL_BLOB );
        if ( !$stmt->execute() ) {
            $log->criticalf(
                'Could not insert content for id %d: %s',
                $id,
                $DBI::errstr,
            );

            exit 1;
        }
    }
}

sub retrieve_content {
    my ( $self, $id ) = @_;
    my $sql  = q{SELECT content FROM data WHERE id = ?};
    my $stmt = $self->dbh->prepare($sql);

    if ( !$stmt ) {
        $log->criticalf(
            'Could not prepare statement [%s] => %s',
            $sql,
            $DBI::errstr,
        );

        exit 1;
    }

    $stmt->bind_param(1, $id, SQL_VARCHAR);
    if ( !$stmt->execute() ) {
        $log->criticalf(
            'Could not retrieve content for id %d: %s',
            $id,
            $DBI::errstr,
        );

        exit 1;
    }

    my $all_content = $stmt->fetchall_arrayref();
    if ( !$all_content || @{$all_content} != 1 ) {
        $log->criticalf(
            'Failed to retrieve exactly one row for id %d: %s',
            $id,
        );

        exit 1;
    }

    return $all_content->[0];
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=pod
