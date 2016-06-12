package Geo::SpatialDB::Location;
use Moo 2;
use namespace::clean;

extends 'Geo::SpatialDB::Entity';

has lat => ( is => 'rw' );
has lon => ( is => 'rw' );
has rad => ( is => 'rw' );

1;
