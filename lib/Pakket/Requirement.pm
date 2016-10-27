package Pakket::Requirement;
# ABSTRACT: A Pakket requirement

use Moose;
use MooseX::StrictConstructor;
use Carp ();
use Log::Any        qw< $log       >;
use List::Util      qw< first      >;
use Module::Runtime qw< use_module >;

use constant {
    'VERSIONING_CLASSES' => {
        # Perl's versioning is likely to be a good default
        ''       => 'Pakket::Versioning::Default',
        'perl'   => 'Pakket::Versioning::Default',
        'native' => 'Pakket::Versioning::Default',
        'nodejs' => 'Pakket::Versioning::SemVer',
    },
};

has 'category' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'name' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'versions' => (
    'is'       => 'ro',
    'isa'      => 'ArrayRef',
    'required' => 1,
);

has 'exact_version' => (
    'is'  => 'ro',
    'isa' => 'Str',
);

has 'version_range' => (
    'is'  => 'ro',
    'isa' => 'Str',
);

has 'versioning_class' => (
    'is'        => 'ro',
    'isa'       => 'Str',
    'lazy'      => 1,
    'builder'   => '_build_versioning_class',
);

has 'latest_version' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'lazy'    => 1,
    'builder' => '_build_latest_version',
);

has 'version_resolver' => (
    'is'      => 'ro',
    'does'    => 'Pakket::Role::Versioning',
    'lazy'    => 1,
    'builder' => '_build_version_resolver',
);

sub BUILDARGS {
    my $class = shift;
    my %args  = ( @_ == 1 and is_plain_hashref( $_[0] ) )
                ? %{ $_[0] }
                : @_;

    $args{'exact_version'} xor $args{'version_range'}
        or Carp::croak("Either 'exact_version' or 'version_range' required");

    return \%args;
}

sub _build_versioning_class {
    my $self     = shift;
    my $category = $self->category;

    exists VERSIONING_CLASSES()->{$category}
        and return VERSIONING_CLASSES()->{$category};

    return VERSIONING_CLASSES()->{''};
}

sub _build_version_resolver {
    my $self  = shift;
    my $class = $self->versioning_class;

    return use_module($class)->new( 'versions' => $self->versions );
}

sub _build_latest_version {
    my $self     = shift;
    my $versions = $self->versions;

    # If we have an exact version, there is no resolving necessary
    # Just find if this exact version is a known version
    if ( defined $self->exact_version ) {
        my $full_name = sprintf '%s/%s=%s',
            $self->name, $self->category, $self->exact_version;

        print("Required: $full_name");
        $log->debug("Required: $full_name");

        if ( !first { $_ eq $self->exact_version } @{ $self->versions } ) {
            $log->criticalf(
                'Could not find version %s in index (%s)',
                $self->exact_version, $full_name
            );

            exit 1;
        }

        return $self->exact_version;
    }

    # Otherwise, we'll need to resolve it from the version range
    my $full_name = sprintf '%s/%s', $self->category, $self->name;
    $log->debugf(
        'Required: %s (%s)',
        $full_name, $self->version_range,
    );

    my $version
        = $self->version_resolver->get_latest_version( $self->version_range );

    if ($version) {
        $log->debugf( 'Found: %s=%s', $full_name, $version );
        return $version;
    }

    $log->criticalf(
        'Could not find version %s in index (%s)',
        $self->version_range, $full_name,
    );

    exit 1;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
