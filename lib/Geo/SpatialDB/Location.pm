package Geo::SpatialDB::Location;
use Moo 2;
use namespace::clean;

extends 'Geo::SpatialDB::Entity';

has rel => ( is => 'rw' ); # arrayref of each entity ID related to this location
has lat => ( is => 'rw' );
has lon => ( is => 'rw' );
has rad => ( is => 'rw' ); # in meters

1;
