#!/usr/bin/perl
use strict;
use warnings;

use File::Basename 'basename';
use MetaCPAN::Client;

$|++;

# find metacpan-example/configs/perl/ -type d -exec basename {} \; | sort
my @dists = @ARGV or die "$0 DISTRIBUTIONS\n";

my $mcpan = MetaCPAN::Client->new;
foreach my $dist_name (@dists) {
    my $release = $mcpan->release($dist_name);
    my $url     = $release->download_url;
    -f basename($url) and next;
    print "-> ", $release->name, "\n";
    system("wget $url");
}
