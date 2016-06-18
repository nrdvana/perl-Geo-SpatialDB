package Geo::SpatialDB::Path;

use Moo 2;
use namespace::clean;

# ABSTRACT: A connected sequence of points on the map

has id  => ( is => 'rw' );
has seq => ( is => 'rw' );

1;
