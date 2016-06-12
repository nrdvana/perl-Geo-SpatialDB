package Geo::SpatialDB::Area;
use Moo 2;
use namespace::clean;

extends 'Geo::SpatialDB::Entity';

has polygons => ( is => 'rw' );
has approx   => ( is => 'rw' );

1;
