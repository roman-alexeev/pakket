package Pakket::Constants; ## no critic (Subroutines::ProhibitExportingUndeclaredSubs)
# ABSTRACT: Constants used in Pakket

use strict;
use warnings;
use parent 'Exporter';

use constant {
    'PARCEL_EXTENSION'     => 'pkt',
    'PARCEL_FILES_DIR'     => 'files',
    'PARCEL_METADATA_FILE' => 'meta.json',

    # CATEGORY/PACKAGE                 == latest version, latest release
    # CATEGORY/PACKAGE=VERSION         == Exact version, latest release
    # CATEGORY/PACKAGE=VERSION:RELEASE == Exact version and release
    'PAKKET_PACKAGE_SPEC'  => qr{
        ^
        ( [^/]+ )       # category
        /
        ( [^=]+ )       # name
        (?:
            =
            ( [^:]+ )   # optional version
            (?:
                :
                (.*)    # optional release
            )?
        )?
        $
    }xms,

    'PAKKET_LATEST_VERSION' => 'LATEST',
    'PAKKET_DEFAULT_RELEASE' => 1,

    'PAKKET_INFO_FILE'      => 'info.json',
};

our @EXPORT_OK = qw<
    PARCEL_EXTENSION
    PARCEL_FILES_DIR
    PARCEL_METADATA_FILE
    PAKKET_PACKAGE_SPEC
    PAKKET_LATEST_VERSION
    PAKKET_DEFAULT_RELEASE
    PAKKET_INFO_FILE
>;

1;
