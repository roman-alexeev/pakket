package Pakket::Constants; ## no critic (Subroutines::ProhibitExportingUndeclaredSubs)
# ABSTRACT: Constants used in Pakket

use strict;
use warnings;
use parent 'Exporter';

use constant {
    'PARCEL_EXTENSION'     => 'pkt',
    'PARCEL_FILES_DIR'     => 'files',
    'PARCEL_METADATA_FILE' => 'meta.json',
};

our @EXPORT_OK = qw<
    PARCEL_EXTENSION
    PARCEL_FILES_DIR
    PARCEL_METADATA_FILE
>;

1;
