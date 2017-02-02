package Pakket::Bundler;
# ABSTRACT: Bundle pakket packages into a parcel file

use Moose;
use MooseX::StrictConstructor;
use JSON::MaybeXS;
use File::Spec;
use Path::Tiny        qw< path >;
use Types::Path::Tiny qw< AbsPath >;
use Log::Any          qw< $log >;

use Pakket::Package;
use Pakket::Repository::Parcel;

use Pakket::Constants qw<
    PARCEL_FILES_DIR
    PARCEL_METADATA_FILE
>;

use constant {
    'BUNDLE_DIR_TEMPLATE' => 'BUNDLE-XXXXXX',
};

has 'parcel_repo' => (
    'is'      => 'ro',
    'isa'     => 'Pakket::Repository::Parcel',
    'lazy'    => 1,
    'builder' => '_build_parcel_repo',
);

has 'bundle_dir' => (
    'is'      => 'ro',
    'isa'     => AbsPath,
    'coerce'  => 1,
    'default' => sub { return path('output')->absolute },
);

has 'files_manifest' => (
    'is'      => 'ro',
    'isa'     => 'HashRef',
    'default' => sub { return +{} },
);

# We're starting with a local repo
# but in the future this will be dictated from a configuration
sub _build_parcel_repo {
    my $self = shift;

    # Use default now for now, but use our directory at least
    return Pakket::Repository::Parcel->new(
        'directory' => $self->bundle_dir,
    );
}

sub bundle {
    my ( $self, $build_dir, $pkg_data, $files ) = @_;

    my (
        $package_category, $package_name,
        $package_version,  $package_spec,
    ) = @{$pkg_data}{qw< category name version spec >};

    my $original_dir = Path::Tiny->cwd;

    # totally arbitrary, maybe add to constants?
    my $parcel_dir_path = Path::Tiny->tempdir(
        'TEMPLATE' => BUNDLE_DIR_TEMPLATE(),
        'CLEANUP'  => 1,
    );

    $parcel_dir_path->child( PARCEL_FILES_DIR() )->mkpath;

    chdir $parcel_dir_path->child( PARCEL_FILES_DIR() )->stringify;

    foreach my $orig_file ( keys %{$files} ) {
        $log->debug("Bundling $orig_file");
        my $new_fullname = $self->_rebase_build_to_output_dir(
            $build_dir, $orig_file,
        );

        -e $new_fullname
            and die 'Odd. File already seems to exist in packaging dir. '
                  . "Stopping.\n";

        # create directories
        $new_fullname->parent->mkpath;

        # regular file
        if ( $files->{$orig_file} eq '' ) {
            path($orig_file)->copy($new_fullname)
                or die "Failed to copy $orig_file to $new_fullname\n";

            my $raw_mode = ( stat($orig_file) )[2];
            my $mode_str = sprintf '%04o', $raw_mode & oct('07777');
            chmod oct($mode_str), $new_fullname;
        } else {
            my $new_symlink = $self->_rebase_build_to_output_dir(
                $build_dir, $files->{$orig_file},
            );

            my $previous_dir = Path::Tiny->cwd;
            chdir $new_fullname->parent;
            symlink $new_symlink, $new_fullname->basename;
            chdir $previous_dir;
        }
    }

    ## no critic qw(ValuesAndExpressions::ProhibitLongChainsOfMethodCalls)
    path( PARCEL_METADATA_FILE() )->spew_utf8(
        JSON::MaybeXS->new->pretty->canonical->encode($package_spec),
    );

    chdir '..';

    # FIXME: This is because the Bundler isn't receiving a
    #        Pakket::Package object
    my $pkg_object = Pakket::Package->new_from_spec($package_spec);
    $log->infof( 'Creating parcel file for %s', $pkg_object->full_name );

    # The lovely thing here is that is creates a parcel file from the
    # bundled directory, which gets cleaned up automatically
    $self->parcel_repo->store_package_parcel(
        $pkg_object,
        $parcel_dir_path,
    );

    chdir $original_dir;

    return;
}

sub _rebase_build_to_output_dir {
    my ( $self, $build_dir, $orig_filename ) = @_;
    ( my $new_filename = $orig_filename ) =~ s/^$build_dir//ms;
    my @parts = File::Spec->splitdir($new_filename);

    # in case the path is absolute (leading slash)
    # the split function will generate an empty first element
    # if it's relative, it will have value and shouldn't be removed
    $parts[0] eq '' and shift @parts;

    return path(@parts);
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__
