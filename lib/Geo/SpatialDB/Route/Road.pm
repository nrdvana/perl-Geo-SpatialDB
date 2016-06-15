package Geo::SpatialDB::Route::Road;
use Moo 2;
use namespace::clean;

extends 'Geo::SpatialDB::Route';

has oneway   => ( is => 'rw' );
has speed    => ( is => 'rw' );
has names    => ( is => 'rw' );

1;
