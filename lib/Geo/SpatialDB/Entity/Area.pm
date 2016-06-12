package Geo::SpatialDB::Entity::Area;
use Moo 2;
use namespace::clean;

extends 'Geo::SpatialDB::Entity';

has polygons => ( is => 'rw' );
has approx   => ( is => 'rw' );

sub taxonomy { 'area' }

1;
