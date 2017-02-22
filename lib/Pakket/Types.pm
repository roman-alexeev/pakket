package Pakket::Types;
# ABSTRACT: Type definitions for Pakket

use strict;
use warnings;

use Moose::Util::TypeConstraints;
use Log::Any qw< $log >;
use Safe::Isa;
use Module::Runtime qw< require_module >;
use Pakket::Constants qw<
    PAKKET_LATEST_VERSION
    PAKKET_DEFAULT_RELEASE
>;

# PakketRepositoryBackend

sub _coerce_backend_from_arrayref {
    my $backend_data = shift;
    my ( $subclass, @args ) = @{$backend_data};
    my $class = "Pakket::Repository::Backend::$subclass";

    eval { require_module($class); 1; } or do {
        die $log->critical("Failed to load backend '$class': $@");
    };

    return $class->new(@args);
}

subtype 'PakketRepositoryBackend', as 'Object', where {
    $_->$_isa('ARRAY') || $_->$_does('Pakket::Role::Repository::Backend')
}, message {
    'Must be a Pakket::Repository::Backend object or an arrayref'
};

coerce 'PakketRepositoryBackend', from 'ArrayRef',
    via { return _coerce_backend_from_arrayref($_); };

# PakketVersion

subtype 'PakketVersion', as 'Str';

coerce 'PakketVersion', from 'Undef',
    via { return PAKKET_LATEST_VERSION() };

# PakketRelease

subtype 'PakketRelease', as 'Str';

coerce 'PakketRelease', from 'Undef',
    via { return PAKKET_DEFAULT_RELEASE() };

no Moose::Util::TypeConstraints;

1;

__END__

=pod
