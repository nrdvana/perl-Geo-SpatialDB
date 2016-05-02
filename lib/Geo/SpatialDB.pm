package Geo::SpatialDB;
use Moo 2;
use Carp;
use namespace::clean;

has zoom_levels;
has indexed_tags;
has entity_types;
has entities;

sub find( lat, lon, lat, lon, min_radius, max_radius, categories ) {
}

1;
