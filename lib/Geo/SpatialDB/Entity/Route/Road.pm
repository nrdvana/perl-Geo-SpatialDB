package Geo::SpatialDB::Entity::Route::Road;
use Moo 2;
use namespace::clean;

extends 'Geo::SpatialDB::Entity::Route';

has oneway => ( is => 'rw' );
has lanes  => ( is => 'rw' );
has speed  => ( is => 'rw' );
has names  => ( is => 'rw' );

sub taxonomy { 'rt' }

1;
