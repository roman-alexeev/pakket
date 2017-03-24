package Pakket::Utils::Repository;

use strict;
use warnings;

use Path::Tiny qw< path >;
use parent 'Exporter';

our @EXPORT_OK = (qw< gen_repo_config >);

my %file_ext = (
    'spec'   => 'ini',
    'source' => 'spkt',
    'parcel' => 'pkt',
);

sub gen_repo_config {
    my ( $self, $type, $directory ) = @_;
    $directory or return;

    if ( $directory =~ m{^/} ) {
        my $path = path($directory);
        $path->exists && $path->is_dir
            or die "Bad directory for $type repo: $path\n";

        return [
            'File',
            'directory'      => $directory,
            'file_extension' => $file_ext{$type},
        ];

    } elsif ( $directory =~ m{^(https?)://([^/:]+):?([^/]+)?(/.*)?$} ) {
        my ( $protocol, $host, $port, $base_path ) = ( $1, $2, $3, $4 );
        $port or $port = $protocol eq 'http' ? 80 : 443;

        return [
            'HTTP',
            'host'      => $host,
            'port'      => $port,
            'base_path' => $base_path,
        ];
    }

    return;
}

1;
__END__
