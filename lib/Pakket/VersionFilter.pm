package Pakket::VersionFilter;
# ABSTRACT: An object representing a version filter

use Moose;
use MooseX::StrictConstructor;

use version 0.77;

has 'filter_string' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'filters' => (
    'is'      => 'ro',
    'isa'     => 'ArrayRef',
    'lazy'    => 1,
    'builder' => '_build_filters',
);

sub _build_filters {
    my $self = shift;

    # A filter string is a comma-separated list of conditions
    # A condition is of the form "OP VER"
    # OP is >=, <=, !=, ==, >, <
    # VER is a version string valid for the version module
    # Whitespace is ignored
    my @conditions = split(/,/, $self->filter_string);
    my @filters;
    foreach my $condition (@conditions) {
        my @filter = $condition =~ /^\s*(>=|<=|==|!=|>|<)\s*(\S*)\s*$/;
        push @filters, \@filter;
    }

    return \@filters;
}

sub valid_condition {
    my ($condition, $parsed_version) = @_;
    my $cmp = $parsed_version <=> version->parse($condition->[1]);

    $condition->[0] eq '>=' and return $cmp >= 0;
    $condition->[0] eq '<=' and return $cmp <= 0;
    $condition->[0] eq '!=' and return $cmp != 0;
    $condition->[0] eq '==' and return $cmp == 0;
    $condition->[0] eq '>'  and return $cmp >  0;
    $condition->[0] eq '<'  and return $cmp <  0;

    return 0;
}

sub match_version {
    my ( $self, $version ) = @_;
    my $filters = $self->filters;
    my $parsed_version = version->parse($version);
    foreach my $filter (@$filters) {
        valid_condition($filter, $parsed_version)
            or return 0;
    }
    return 1;
}

sub filter_versions {
    my ( $self, $versions ) = @_;
    my @filtered;
    foreach my $version (@$versions) {
        $self->match_version($version)
            or next;
        push @filtered, $version;
    }
    return \@filtered;
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
