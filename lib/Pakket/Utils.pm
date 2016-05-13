package Pakket::Utils;

# ABSTRACT: Utilities for Pakket
use strict;
use warnings;
use Exporter qw< import >;
use Path::Tiny qw< path >;
use File::HomeDir;

our @EXPORT_OK = qw< is_writeable >;

sub is_writeable {
    my $path = shift; # Path::Tiny objects

    while ( !$path->is_rootdir ) {
        $path->exists and return -w $path;
        $path = $path->parent;
    }

    return -w $path;
}

1;

__END__
