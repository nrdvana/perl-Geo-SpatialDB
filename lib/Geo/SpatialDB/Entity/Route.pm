package Geo::SpatialDB::Entity::Route;

use Moo 2;
use namespace::clean;

# ABSTRACT: A logical entity encompasing one or more RouteSegments

extends 'Geo::SpatialDB::Entity';

has segments  => ( is => 'rw' );
has names     => ( is => 'rw' );

sub components {
	my $self= shift;
	return @{ $self->segments };
}

1;
