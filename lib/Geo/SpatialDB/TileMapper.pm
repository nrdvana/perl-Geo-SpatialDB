package Geo::SpatialDB::TileMapper;
use Moo::Role;

# VERSION

=head1 DESCRIPTION

This role defines the API for TileMappers, which divide the globe into
non-overlapping tiles each with a distinct ID.

=head1 METHODS

=head2 tiles_for_area

  my $tile_ids= $mapper->tiles_for_area($llbox_or_llrad);

Returns an array of all tile IDs which intersect the lat/lon range provided.
The argument may be a L<Geo::SpatialDB::Math::LLBox> or L<Geo::SpatialDB::Math::LLRad>.
Tile IDs must be scalars, and may be binary data, but integers are recommended.

=head2 tile_at

  my $tile_id= $mapper->tile_at($lat0, $lon0);

Return the single tile which contains the given coordinate.
Implementations are free to decide whch tile an edge belongs to, should a
coordinate land exactly on the boundary, but the mapping must be consistent.

=head2 tile_polygon

  my @verticies= $mapper->tile_polygon($tile_id);

Return a list of spherical coordinates defining the vertices of a tile in
counter-clockwise winding order when viewing the tile from above.
(counter-clockwise is the OpenGL default)

=cut

requires 'tiles_for_area';
requires 'tile_at';
requires 'tile_polygon';

1;

