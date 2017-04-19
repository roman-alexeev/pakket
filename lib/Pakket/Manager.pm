package Pakket::Manager;
# ABSTRACT: Manage pakket packages and repos

use Moose;
use Log::Any qw< $log >;
use Carp     qw< croak >;

use Pakket::Log;
use Pakket::Scaffolder::Perl;

has 'config' => (
    'is'        => 'ro',
    'isa'       => 'HashRef',
    'default'   => sub { +{} },
);

has 'category' => (
    'is'        => 'ro',
    'isa'       => 'Str',
    'lazy'      => 1,
    'builder'   => '_build_category',
);

has 'cache_dir' => (
    'is'        => 'ro',
    'isa'       => 'Maybe[Str]',
);

has 'cpanfile' => (
    'is'        => 'ro',
    'isa'       => 'Maybe[Str]',
);

has 'package' => (
    'is'        => 'ro',
    'isa'       => 'Maybe[Pakket::Package]',
);

has 'phases' => (
    'is'        => 'ro',
    'isa'       => 'Maybe[ArrayRef]',
);

has 'file_02packages' => (
    'is'        => 'ro',
    'isa'       => 'Maybe[Str]',
);

has 'no_deps' => (
    'is'        => 'ro',
    'isa'       => 'Bool',
    'default'   => 0,
);

has 'is_local' => (
    'is'        => 'ro',
    'isa'       => 'Bool',
    'default'   => 0,
);

has 'requires_only' => (
    'is'        => 'ro',
    'isa'       => 'Bool',
    'default'   => 0,
);

sub _build_category {
    my $self = shift;
    $self->{'cpanfile'} and return 'perl';
    return $self->package->category;
}

sub list_ids {
    my ( $self, $type ) = @_;
    my $repo = $self->_get_repo($type);
    print "$_\n" for sort @{ $repo->all_object_ids };
}

sub show_package_config {
    my $self = shift;
    my $repo = $self->_get_repo('spec');
    my $spec = $repo->retrieve_package_spec( $self->package );

    my ( $category, $name, $version, $release ) =
        @{ $spec->{'Package'} }{qw< category name version release >};

    print <<"SHOW";

# PACKAGE:

category: $category
name:     $name
version:  $version
release:  $release

# DEPENDENCIES:

SHOW

    for my $c ( sort keys %{ $spec->{'Prereqs'} } ) {
        for my $p ( sort keys %{ $spec->{'Prereqs'}{$c} } ) {
            print "$c/$p:\n";
            for my $n ( sort keys %{ $spec->{'Prereqs'}{$c}{$p} } ) {
                my $v = $spec->{'Prereqs'}{$c}{$p}{$n}{'version'};
                print "- $n-$v\n";
            }
            print "\n";
        }
    }

    # TODO: reverse dependencies (requires map)
}

sub add_package {
    my $self = shift;
    $self->_get_scaffolder->run;
}

sub remove_package_source {
    my $self = shift;
    my $repo = $self->_get_repo('source');
    $repo->remove_package_source( $self->package );
    $log->info( sprintf("Removed %s from the source repo.", $self->package->id ) );
}

sub remove_package_spec {
    my $self = shift;
    my $repo = $self->_get_repo('spec');
    $repo->remove_package_spec( $self->package );
    $log->info( sprintf("Removed %s from the spec repo.", $self->package->id ) );
}

sub remove_package_parcel {
    my $self = shift;
    my $repo = $self->_get_repo('parcel');
    $repo->remove_package_parcel( $self->package );
    $log->info( sprintf("Removed %s from the parcel repo.", $self->package->id ) );
}

sub add_dependency {
    my ( $self, $dependency ) = @_;
    $self->_package_dependency_edit($dependency, 'add');
}

sub remove_dependency {
    my ( $self, $dependency ) = @_;
    $self->_package_dependency_edit($dependency, 'remove');
}

sub _package_dependency_edit {
    my ( $self, $dependency, $cmd ) = @_;
    my $repo = $self->_get_repo('spec');
    my $spec = $repo->retrieve_package_spec( $self->package );

    my $dep_name    = $dependency->{'name'};
    my $dep_version = $dependency->{'version'};

    my ( $category, $phase ) = @{$dependency}{qw< category phase >};

    my $dep_exists = ( defined $spec->{'Prereqs'}{$category}{$phase}{$dep_name}
                           and $spec->{'Prereqs'}{$category}{$phase}{$dep_name}{'version'} eq $dep_version );

    my $name = $self->package->name;

    if ( $cmd eq 'add' ) {
        if ( $dep_exists ) {
            $log->info( sprintf("%s is already a %s dependency for %s.",
                                $dep_name, $phase, $name) );
            exit 1;
        }

        $spec->{'Prereqs'}{$category}{$phase}{$dep_name} = +{
            version => $dep_version
        };

        $log->info( sprintf("Added %s as %s dependency for %s.",
                            $dep_name, $phase, $name) );

    } elsif ( $cmd eq 'remove' ) {
        if ( !$dep_exists ) {
            $log->info( sprintf("%s is not a %s dependency for %s.",
                                $dep_name, $phase, $name) );
            exit 1;
        }

        delete $spec->{'Prereqs'}{$category}{$phase}{$dep_name};

        $log->info( sprintf("Removed %s as %s dependency for %s.",
                            $dep_name, $phase, $name) );
    }

    $repo->store_package_spec($self->package, $spec);
}

sub _get_repo {
    my ( $self, $key ) = @_;
    my $class = 'Pakket::Repository::' . ucfirst($key);
    return $class->new(
        'backend' => $self->config->{'repositories'}{$key},
    );
}

sub _get_scaffolder {
    my $self = shift;

    $self->category eq 'perl'
        and return $self->_gen_scaffolder_perl;

    croak("failed to create a scaffolder\n");
}

sub _gen_scaffolder_perl {
    my $self = shift;

    my %params = (
        'config'   => $self->config,
        'phases'   => $self->phases,
        'no_deps'  => ( $self->is_local ? 1 : $self->no_deps ),
        'is_local' => $self->is_local,
        ( 'types'  => ['requires'] )x!! $self->requires_only,
    );

    if ( $self->cpanfile ) {
        $params{'cpanfile'} = $self->cpanfile;

    } else {
        $params{'module'}  = $self->package->name;
        $params{'version'} = defined $self->package->version
            # hack to pass exact version in prereq syntax
            ? ( $self->is_local ? '' : '==' ) . $self->package->version
            : undef;
    }

    $self->cache_dir
        and $params{'cache_dir'} = $self->cache_dir;

    $self->file_02packages
        and $params{'file_02packages'} = $self->file_02packages;

    return Pakket::Scaffolder::Perl->new(%params);
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__
