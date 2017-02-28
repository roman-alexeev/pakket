package Pakket::Config;
# ABSTRACT: Read and represent Pakket configurations

use Moose;
use MooseX::StrictConstructor;
use Config::Any;
use Path::Tiny        qw< path >;
use Types::Path::Tiny qw< Path >;

has 'prefix' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'default' => sub { return '.pakket'; },
);

has 'dir' => (
    'is'      => 'ro',
    'isa'     => Path,
    'coerce'  => 1,
    'default' => sub { return path('~'); },
);

has 'extensions' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'default' => sub { return [qw< json yaml yml conf cfg >] },
);

has 'files' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'lazy'    => 1,
    'default' => sub {
        my $self        = shift;
        my $prefix_path = $self->dir->child( $self->prefix );

        return [ map "$prefix_path.$_", @{ $self->extensions } ];
    },
);

sub read_config {
    my $self   = shift;
    my $config = Config::Any->load_files({
        'files'   => $self->files,
        'use_ext' => 1,
    });

    my %cfg;
    foreach my $config_chunk ( @{$config} ) {
        foreach my $filename ( keys %{$config_chunk} ) {
            my %config_part = %{ $config_chunk->{$filename} };
            @cfg{ keys(%config_part) } = values %config_part;
        }
    }

    return \%cfg;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=pod
