#!/usr/bin/env perl
use strict;
use warnings;

use MetaCPAN::Client;
use Getopt::Long;
use Path::Tiny;
use TOML;

Getopt::Long::GetOptions(
    "source-dir=s" => \my $source_dir,
    "spec-dir=s"   => \my $spec_dir,
);
-d $spec_dir   or die "Invalid spec dir";
-d $source_dir or die "Invalid source dir";

my %seen;
my $iter = path($spec_dir)->iterator( { recurse => 1 } );
while ( my $next = $iter->() ) {
    if ( not $next->is_file or not $next =~ /\.toml$/ ) {
        next;
    }

    my $module = TOML::from_toml( $next->slurp_utf8 );

    $seen{"$module->{Package}{name}-$module->{Package}{version}"} = undef;

    for my $prereqs ( values( %{ $module->{Prereqs}{perl} } ) ) {
        for my $dist ( keys(%$prereqs) ) {
            if ( $dist eq "perl" ) {
                next;
            }
            $seen{"$dist-$prereqs->{$dist}{version}"} = undef;
        }
    }
}

my @to_fetch = sort( keys(%seen) );
my $mcpan    = MetaCPAN::Client->new;

open( my $pipe, "| wget --directory-prefix='$source_dir' --input-file=-" );

for my $dist (@to_fetch) {
    my $res = $mcpan->release(
        {
            all => [ { name => $dist } ],
        }
    );
    if ( $res->total == 0 ) {
        warn "Couldn't find $dist on MetaCPAN";
        next;
    }

    while ( my $release = $res->next ) {
        print $pipe $release->download_url, "\n";
    }
}

close($pipe);
