package Geo::SpatialDB::Route;
use Moo 2;
use namespace::clean;

extends 'Geo::SpatialDB::Entity';

has segments => ( is => 'rw' );

1;
