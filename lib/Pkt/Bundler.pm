package Pkt::Bundler;
# ABSTRACT: Bundle pkt packages into a package file

use Moose;
use Path::Tiny qw< path >;
use File::Spec;
use Types::Path::Tiny qw< AbsPath >;

use constant {
    PKT_EXTENSION => 'pkt',
};

# XXX should we separate the development files into development
# package files, the way dists usually do?
# pro: smaller binary packages with JUST the libraries
# con: we'll probably need to maintain a list of files because we don't
#      know which files are needed during run-time, we will need to
#      maintain two different packages, it adds complexity
# (plus, the size of development files are rather small)

# this is where we bundle it all
# at the end the file will end up here
# and it could be copied by other classes (like the Builder)
# to the appropriate location
has bundle_dir => (
    is      => 'ro',
    isa     => AbsPath,
    default => sub { path('output')->absolute },
);

has files_manifest => (
    is      => 'ro',
    isa     => 'HashRef',
    default => sub { +{} },
);

sub bundle {
    my ( $self, $build_dir, $category, $package_name, $files ) = @_;

    my $original_dir = Path::Tiny->cwd;

    # totally arbitrary, maybe add to constants?
    my $bundle_path = Path::Tiny->tempdir(
        TEMPLATE => 'BUNDLE-XXXXXX',
        CLEANUP  => 1,
    );

    chdir $bundle_path->stringify;

    foreach my $orig_file ( keys %{$files} ) {
        my $new_fullname = $self->_rebase_build_to_output_dir(
            $build_dir, $orig_file
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
            # FIXME: Perl::Critic complains about this if:
            # 07777
            # is used instead of:
            # oct('07777')
            # even though perldoc perlfunc suggests it
            my $mode_str = sprintf '%04o', $raw_mode & oct('07777');
            chmod oct($mode_str), $new_fullname;
        } else {
            my $new_symlink = $self->_rebase_build_to_output_dir(
                $build_dir, $files->{$orig_file}
            );

            # there is a "FIXME" comment above on supporting absolute
            # symlinks. Until that is fixed, we can at least know for
            # sure that this symlink is relative, which means we can
            # safely link to it directly
            # -- SX.

            my $previous_dir = Path::Tiny->cwd;
            chdir $new_fullname->parent;
            symlink $new_symlink, $new_fullname->basename;
            chdir $previous_dir;
        }
    }

    # FIXME: I want to add versioning here for the file
    # but that means pulling the version variable in this sub
    # and this sub is already called from a weird chain that needs
    # to be cleaned up, so we'll do it after
    # -- SX.

    # FIXME: should we include the metadata (currently the TOML file)
    # in this archive?

    my $bundle_filename = path( join '.', $package_name, PKT_EXTENSION );

    # TODO: use Archive::Any instead?
    system "tar -cJf $bundle_filename *";
    my $new_location = path( $self->bundle_dir, $category, $package_name );
    $new_location->mkpath;

    # A lot of Unix systems simply don't allow the mv command to work between different devices
    # (or even different partitions on the same device).
    # The solution is to copy the file over, and then delete the original - or use GNU mv,
    # which will do the same thing automaticaly.
    #   -- http://www.perlmonks.org/?node_id=338699
    # (this happened because it was installed in /tmp which was a different FS -- SX.)
    $bundle_filename->copy( path( $new_location, $bundle_filename ) );
    $bundle_filename->remove();

    chdir $original_dir;
}

sub _rebase_build_to_output_dir {
    my ( $self, $build_dir, $orig_filename ) = @_;
    ( my $new_filename = $orig_filename ) =~ s/^$build_dir//;
    my @parts = File::Spec->splitdir($new_filename);

    # in case the path is absolute (leading slash)
    # the split function will generate an empty first element
    # if it's relative, it will have value and shouldn't be removed
    $parts[0] eq '' and shift @parts;

    return path(@parts);
}

__PACKAGE__->meta->make_immutable;

1;

__END__
