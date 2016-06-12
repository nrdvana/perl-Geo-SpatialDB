package Geo::SpatialDB::Entity::Route;
use Moo 2;
use namespace::clean;

extends 'Geo::SpatialDB::Entity';

has path     => ( is => 'rw' );

sub taxonomy { 'rt' }

1;
