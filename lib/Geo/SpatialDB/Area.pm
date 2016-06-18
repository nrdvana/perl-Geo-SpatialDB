package Geo::SpatialDB::Area;

use Moo 2;
use namespace::clean;

# ABSTRACT: Object representing (possibly non-contiguous area) on the map

extends 'Geo::SpatialDB::Entity';

has polygons => ( is => 'rw' );
has approx   => ( is => 'rw' );

1;
