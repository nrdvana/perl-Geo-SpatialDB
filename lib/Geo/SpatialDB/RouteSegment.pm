package Geo::SpatialDB::RouteSegment;
use Moo 2;
use namespace::clean;

extends 'Geo::SpatialDB::Entity';

has path   => ( is => 'rw' );
has oneway => ( is => 'rw' );
has lanes  => ( is => 'rw' );
has speed  => ( is => 'rw' );

1;
