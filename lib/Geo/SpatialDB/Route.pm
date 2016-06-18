package Geo::SpatialDB::Route;

use Moo 2;
use namespace::clean;

# ABSTRACT: A logical entity encompasing one or more RouteSegments

extends 'Geo::SpatialDB::Entity';

has segments => ( is => 'rw' );

1;
