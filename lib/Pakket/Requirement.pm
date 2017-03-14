package Pakket::Requirement;
# ABSTRACT: A Pakket requirement

use Moose;
use MooseX::StrictConstructor;

use Log::Any          qw< $log >;
use Pakket::Constants qw<
    PAKKET_PACKAGE_SPEC
    PAKKET_DEFAULT_RELEASE
>;
use Pakket::Types;

with qw< Pakket::Role::BasicPackageAttrs >;

has [qw< category name >] => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'version' => (
    'is'       => 'ro',
    'isa'      => 'PakketVersion',
    'coerce'   => 1,
    'required' => 1,
);

has 'release' => (
    'is'      => 'ro',
    'isa'     => 'PakketRelease',
    'coerce'  => 1,
    'default' => sub { PAKKET_DEFAULT_RELEASE() },
);

has 'is_bootstrap' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => sub {0},
);

sub new_from_string {
    my ( $class, $req_str ) = @_;

    if ( $req_str !~ PAKKET_PACKAGE_SPEC() ) {
        die $log->critical("Cannot parse $req_str");
    } else {
        # This shuts up Perl::Critic
        return $class->new(
            'category' => $1,
            'name'     => $2,
            'version'  => $3,
            ( 'release'  => $4 )x!! $4,
        );
    }
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
