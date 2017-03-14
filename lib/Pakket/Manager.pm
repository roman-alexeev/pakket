package Pakket::Manager;
# ABSTRACT: Manage pakket packages and repos

use Moose;
use Log::Any qw< $log >;

use Pakket::Log;

has config => (
    is        => 'ro',
    isa       => 'HashRef',
    default   => sub { +{} },
);

has cache_dir => (
    is        => 'ro',
    isa       => 'Maybe[Str]',
);

has cpanfile => (
    is        => 'ro',
    isa       => 'Maybe[Str]',
);

has package => (
    is        => 'ro',
    isa       => 'Maybe[Pakket::Package]',
);

has phases => (
    is        => 'ro',
    isa       => 'Maybe[ArrayRef]',
);

sub list_ids {
    my ( $self, $type ) = @_;
    my $repo = $self->_get_repo($type);
    print "$_\n" for sort @{ $repo->all_object_ids };
}

sub show_package_config {
    my ( $self, $package ) = @_;
    my $repo = $self->_get_repo('spec');
    my $spec = $repo->retrieve_package_spec($package);

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
    my ( $self, $category ) = @_;
    $self->_get_scaffolder($category)->run;
}

sub remove_package_source {
    my ( $self, $package ) = @_;
    my $repo = $self->_get_repo('source');
    $repo->remove_package_source( $package );
    $log->info( sprintf("Removed %s from the source repo.", $package->id ) );
}

sub remove_package_spec {
    my ( $self, $package ) = @_;
    my $repo = $self->_get_repo('spec');
    $repo->remove_package_spec( $package );
    $log->info( sprintf("Removed %s from the spec repo.", $package->id ) );
}

sub add_package_dependency {
    my ( $self, $package, $dependency ) = @_;
    $self->_package_dependency_edit($package, $dependency, 'add');
}

sub remove_package_dependency {
    my ( $self, $package, $dependency ) = @_;
    $self->_package_dependency_edit($package, $dependency, 'remove');
}

sub _package_dependency_edit {
    my ( $self, $package, $dependency, $cmd ) = @_;
    my $repo = $self->_get_repo('spec');
    my $spec = $repo->retrieve_package_spec($package);

    my $dep_name    = $dependency->{'name'};
    my $dep_version = $dependency->{'version'};

    my ( $category, $phase ) = @{$dependency}{qw< category phase >};

    my $dep_exists = ( defined $spec->{'Prereqs'}{$category}{$phase}{$dep_name}
                           and $spec->{'Prereqs'}{$category}{$phase}{$dep_name}{'version'} eq $dep_version );

    if ( $cmd eq 'add' ) {
        if ( $dep_exists ) {
            $log->info( sprintf("%s is already a %s dependency for %s.",
                                $dep_name, $phase, $package->name) );
            exit 1;
        }

        $spec->{'Prereqs'}{$category}{$phase}{$dep_name} = +{
            version => $dep_version
        };

        $log->info( sprintf("Added %s as %s dependency for %s.",
                            $dep_name, $phase, $package->name) );

    } elsif ( $cmd eq 'remove' ) {
        if ( !$dep_exists ) {
            $log->info( sprintf("%s is not a %s dependency for %s.",
                                $dep_name, $phase, $package->name) );
            exit 1;
        }

        delete $spec->{'Prereqs'}{$category}{$phase}{$dep_name};

        $log->info( sprintf("Removed %s as %s dependency for %s.",
                            $dep_name, $phase, $package->name) );
    }

    $repo->store_package_spec($package, $spec);
}

sub _get_repo {
    my ( $self, $key ) = @_;
    my $class = 'Pakket::Repository::' . ucfirst($key);
    return $class->new(
        'backend' => $self->config->{'repositories'}{$key},
    );
}

sub _get_scaffolder {
    my ( $self, $package ) = @_;

    $package->category eq 'perl'
        and return $self->_gen_scaffolder_perl;

    die "failed to create a scaffolder\n";
}

sub _gen_scaffolder_perl {
    my $self = shift;

    my %params = (
        'config' => $self->config,
        'phases' => $self->phases,
    );

    if ( $self->cpanfile ) {
        $params{'cpanfile'} = $self->cpanfile;

    } else {
        $params{'module'}  = $self->package->name;
        $params{'version'} = defined $self->package->version
            # hack to pass exact version in prereq syntax
            ? '=='.$self->package->version
            : undef;
    }

    $self->cache_dir
        and $params{'cache_dir'} = $self->cache_dir;

    return Pakket::Scaffolder::Perl->new(%params);
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__
