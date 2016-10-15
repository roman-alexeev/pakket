package Pakket::Role::Builder;

# ABSTRACT: A role for all builders

use Moose::Role;

with qw< Pakket::Role::RunCommand >;

requires qw< build_package >;

sub generate_env_vars {
    my ( $self, $prefix ) = @_;
    my $lib_path = $self->generate_lib_path($prefix);
    my $bin_path = $self->generate_bin_path($prefix);

    return (
        'CPATH'           => $prefix->child('include')->stringify,
        'LD_LIBRARY_PATH' => $lib_path,
        'LIBRARY_PATH'    => $lib_path,
        'PATH'            => $bin_path,
    );
}

sub generate_lib_path {
    my ( $self, $prefix ) = @_;

    my $lib_path = $prefix->child('lib')->absolute->stringify;
    if ( defined( my $env_library_path = $ENV{'LD_LIBRARY_PATH'} ) ) {
        $lib_path .= ":$env_library_path";
    }

    return $lib_path;
}

sub generate_bin_path {
    my ( $self, $prefix ) = @_;

    my $bin_path = $prefix->child('bin')->absolute->stringify;
    if ( defined( my $env_bin_path = $ENV{'PATH'} ) ) {
        $bin_path .= ":$env_bin_path";
    }

    return $bin_path;
}

no Moose::Role;

1;
