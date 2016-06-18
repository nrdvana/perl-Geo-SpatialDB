package Geo::SpatialDB::RouteSegment;

use Moo 2;
use namespace::clean;

# ABSTRACT: A piece of a Route, represented by a contiguous sequence of points

extends 'Geo::SpatialDB::Entity';

has path   => ( is => 'rw' );
has oneway => ( is => 'rw' );
has lanes  => ( is => 'rw' );
has speed  => ( is => 'rw' );
has routes => ( is => 'rw' );

1;
