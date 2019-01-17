package Geo::SpatialDB::TileMapper;
use Moo::Role;

# VERSION

=head1 DESCRIPTION

This role defines the API for TileMappers, which divide the globe into
non-overlapping tiles each with a distinct ID.

=head1 METHODS

=head2 tiles_in_range

  my @tile_ids= $mapper->tiles_in_range($lat0, $lon0, $lat1, $lon1);

Returns a list of all tile IDs which intersect the lat/lon ranges provided.
Lat/lon coordinates are represented as 30-bit-circle integers.
Tile IDs must be scalars, and may be binary data, but integers are
recommended.

C<$lat0> should be between C<< [-0x40000000 .. $lat1] >> and C<$lat1> should be
between C<< [$lat0 .. 0x40000000] >>, but implementations should not assume this
is true, and should clamp the values before using them if needed.

C<$lon0> and C<$lon1> are treated as modulo 2**32, and iteration can simply be
done on a 32-bit register until it wraps to the new value.

=head2 tile_at

  my $tile_id= $mapper->tile_at($lat0, $lon0);

Return the single tile which contains the given coordinate.
Lat/lon coordinates are represented as 30-bit-circle integers.
Implementations are free to decide whch tile an edge belongs to, should a
coordinate land exactly on the boundary, but the mapping must be consistent.

=head2 tile_polygon

  my @verticies= $mapper->tile_polygon($tile_id);

Return a list of spherical coordinates defining the vertices of a tile in
counter-clockwise winding order when viewing the tile from above.
Lat/lon coordinates returned are represented as 30-bit-circle integers.
(Why clockwise? because it's the OpenGL default)

=cut

1;

