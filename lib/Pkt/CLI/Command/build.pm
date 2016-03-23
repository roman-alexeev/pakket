package Pkt::CLI::Command::build;
# ABSTRACT: The pkt build command

use strict;
use warnings;
use Pkt::CLI -command;
use Pkt::Builder;

# TODO:
# - move all hardcoded values (confs) to constants
# - add make process log (and add it with -v -v)

sub abstract    { 'Build a package' }
sub description { 'Build a package' }

sub opt_spec {
    return (
        [ 'category=s',     'pkt category ("perl", "system", etc.)'    ],
        [ 'build-dir=s',    'use an existing build directory'          ],
        [ 'config-dir=s',   'directory holding the configurations'     ],
        [ 'source-dir=s',   'directory holding the sources'            ],
        [ 'verbose|v',      'verbose log'                              ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    $self->{'category'} = $opt->{'category'};

    $args->[0]
        or $self->usage_error('Must specify package');

    my ( $cat, $package ) = split '/', $args->[0];

    # did we get a full path spec (category/package)
    if ($package) {
        # if there is a category, it *has* to match
        # the category provided by the full spec
        $self->{'category'} && $self->{'category'} ne $cat
            and $self->usage_error(
                sprintf "You specified two categories: '%s' and '%s'\n",
                        $self->{'category'},
                        $cat
            );

        # use the category we got from the full spec if we don't
        # have one defined already
        # (and if we do, they will match anyway - see check above)
        $self->{'category'} //= $cat;
    }

    # if there is no package, the first item (now in $cat)
    # is the package name
    $self->{'package'} = $package || $cat;

    $self->{'category'}
        or $self->usage_error('You must provide a category');

    $self->{'category'}
        or $self->usage_error('I don\'t have a category for this package.');

    if ( $opt->{'build_dir'} ) {
        -d $opt->{'build_dir'}
            or die "You asked to use a build dir that does not exist.\n";
    }

    $self->{'config_dir'} = $opt->{'config_dir'};
    $self->{'source_dir'} = $opt->{'source_dir'};
    $self->{'log'}        = $opt->{'verbose'};
}

sub execute {
    my $self    = shift;
    my $builder = Pkt::Builder->new(
        map +( defined $self->{$_} ? ( $_ => $self->{$_} ) : () ), qw<
            config_dir source_dir build_dir log
        >
    );

    $builder->build( $self->{'category'}, $self->{'package'} );
}

1;

__END__
