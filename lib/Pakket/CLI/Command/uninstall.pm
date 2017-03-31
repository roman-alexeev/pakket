package Pakket::CLI::Command::uninstall;

# ABSTRACT: The pakket uninstall command

use strict;
use warnings;

use Log::Any qw< $log >;
use Log::Any::Adapter;
use IO::Prompt::Tiny qw< prompt >;
use Path::Tiny qw< path >;

use Pakket::CLI '-command';
use Pakket::Uninstaller;
use Pakket::Log;
use Pakket::Package;
use Pakket::Constants qw< PAKKET_PACKAGE_SPEC >;

sub abstract    {'Uninstall a package'}
sub description {'Uninstall a package'}

sub _determine_packages {
    my ( $self, $opt, $args ) = @_;

    my @package_strs
        = defined $opt->{'input_file'}
        ? path( $opt->{'input_file'} )->lines_utf8( { 'chomp' => 1 } )
        : @{$args};

    my @packages;
    foreach my $package_str (@package_strs) {
        my ( $pkg_cat, $pkg_name, $pkg_version, $pkg_release )
            = $package_str =~ PAKKET_PACKAGE_SPEC();

        if ( !$pkg_cat || !$pkg_name ) {
            die $log->critical(
                "Can't parse $package_str. Use format category/package_name");
        }

        push @packages, { 'category' => $pkg_cat, 'name' => $pkg_name };
    }

    return \@packages;
}

sub _validate_arg_lib_dir {
    my ( $self, $opt ) = @_;

    my $pakket_dir = $opt->{'pakket_dir'};

    $pakket_dir
        or $self->usage_error(
        "please define the library dir --pakket-dir <path_to_library>\n");

    path($pakket_dir)->exists
        or $self->usage_error("Library dir: $pakket_dir doesn't exist\n");

    $self->{'pakket_dir'} = $pakket_dir;
}

sub opt_spec {
    return (
        [ 'pakket-dir=s',         'path where installed pakket' ],
        [ 'input-file=s',         'uninstall eveything listed in this file' ],
        [ 'without-dependencies', 'don\'t remove dependencies' ],
        [
            'verbose|v+',
            'verbose output (can be provided multiple times)',
            { 'default' => 1 },
        ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    Log::Any::Adapter->set( 'Dispatch',
        'dispatcher' => Pakket::Log->build_logger( $opt->{'verbose'} ) );

    $self->_validate_arg_lib_dir($opt);
    $opt->{'packages'} = $self->_determine_packages( $opt, $args );
}

sub execute {
    my ( $self, $opt ) = @_;

    my $uninstaller = Pakket::Uninstaller->new(
        'pakket_dir'           => $self->{'pakket_dir'},
        'packages'             => $opt->{'packages'},
        'without_dependencies' => $opt->{'without_dependencies'},
    );

    my @packages_for_uninstall
        = $uninstaller->get_list_of_packages_for_uninstall();

    print "We are going to remove:\n";
    for my $package (@packages_for_uninstall) {
        print "* $package->{category}/$package->{name}\n";
    }

    my $answer = prompt( 'Continue?', 'y' );

    lc $answer eq 'y'
        and $uninstaller->uninstall();

    return;
}

1;

__END__
