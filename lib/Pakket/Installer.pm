package Pakket::Installer;
# ABSTRACT: Install pakket packages into an installation directory

use Moose;
use Path::Tiny        qw< path  >;
use Types::Path::Tiny qw< Path  >;
use File::HomeDir;

# TODO:
# * Recursively install
# * Support .pakket.local (or .pakket.config local file configuration)
# * Support multiple libraries
# * Support active library

# Sample structure:
# ~/.pakket/
#        bin/
#        etc/
#        repos/
#        libraries/
#                  active ->
#

has base_dir => (
    is      => 'ro',
    isa     => Path,
    default => sub {
        my $self = shift;
        # 1. $ENV{'PKT_DIR'}: pre-enabled pakket installation
        $ENV{'PKT_DIR'} && -d $ENV{'PKT_DIR'}
            and return path( $ENV{'PKT_DIR'} );

        # 2. /usr/local/pakket
        my $base_dir = path( Path::Tiny->rootdir, qw< usr local pakket > );
        if ( $base_dir->is_dir && -w $base_dir->stringify ) {
            return $base_dir;
        }

        # 3. local .pakket in home directory
        $base_dir = path( File::HomeDir->my_home, '.pakket' );

        -d $base_dir
            or $base_dir->mkpath;

        # assert directory structure
        my @dirs = (
            $base_dir,
            path( $base_dir, 'library' ),
        );

        foreach my $dir (@dirs) {
            -d $dir or $dir->mkpath;
        }

        return $base_dir;
    },
    coerce  => 1,
);

has install_dir => (
    is      => 'ro',
    isa     => Path,
    lazy    => 1,
    coerce  => 1,
    default => sub {
        my $self = shift;
        path( $self->base_dir, 'library' );
    },
);

# TODO:
# this should be implemented using a fetcher class
# because it might be from HTTP/FTP/Git/Custom/etc.
sub fetch_package;

sub install_file {
    my ( $self, $filename ) = @_;
    my $install_dir = $self->install_dir;
    -d $install_dir
        or $install_dir->mkpath();

    -r( my $bundle_file = path($filename) )
        or die "Bundle file '$filename' does not exist or can't be read\n";

    my $bundle_basename = $bundle_file->basename;
    $bundle_file->copy($install_dir);

    # TODO: Archive::Any might fit here, but it doesn't support XZ
    # introduce a plugin for it? It could be based on Archive::Tar
    # but I'm not sure Archive::Tar support XZ either -- SX.
    System::Command->spawn(
        qw< tar -xJf >, $bundle_basename,
        { cwd => $install_dir },
    );

    $install_dir->child( $bundle_basename )->remove;

    print "Installed $bundle_basename in $install_dir\n";
}


__PACKAGE__->meta->make_immutable;

1;

__END__
