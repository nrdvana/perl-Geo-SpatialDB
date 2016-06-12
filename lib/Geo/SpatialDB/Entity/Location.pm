package Geo::SpatialDB::Entity::Location;
use Moo 2;
use namespace::clean;

extends 'Geo::SpatialDB::Entity';

has lat => ( is => 'rw' );
has lon => ( is => 'rw' );
has rad => ( is => 'rw' );

sub taxonomy { 'loc' }

1;
