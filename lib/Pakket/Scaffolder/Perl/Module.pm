package Pakket::Scaffolder::Perl::Module;
# ABSTRACT: scaffolder: module config representation

use Moose;
use MooseX::StrictConstructor;

has 'name' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => sub {1},
);

has 'version' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => sub {0},
);

has 'phase' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => sub {'runtime'},
);

has 'type' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => sub {'requires'},
);

sub BUILDARGS {
    my ( $class, @args ) = @_;
    my %args = @args == 1 ? %{ $args[0] } : @args;

    if ( $args{'name'} =~ /^ (.+) \@ (.+) $/x ) {
        $args{'name'}    = $1;
        $args{'version'} = "== $2";
    }
    elsif ( $args{'name'} =~ /^ (.+) \~ (.+) $/x ) {
        $args{'name'}    = $1;
        $args{'version'} = $2;
    }

    return \%args;
}

sub prereq_specs {
    my $self = shift;
    return +{
        $self->phase => +{
            $self->type => +{
                $self->name => $self->version,
            },
        },
    };
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
__END__
