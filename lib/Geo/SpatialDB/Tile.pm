package Geo::SpatialDB::Tile;
use Moo 2;
use namespace::clean;

=head1 DESCRIPTION


=head1 ATTRIBUTES

=head2 id

Unique ID for the tile.  Useful for caching.

=head2 lat0

South edge

=head2 lon0

West edge

=head2 lat1

North edge

=head2 lon1

East edge

=head2 areas

Array of partial areas, each a hashref of the form:

  {
    id         => $area_id,
    type       => $taxonomy_spec,
    local_path => [
      [ lat,lon, lat,lon, lat,lon, ... ],
      ...
    ],
    tag_cache  => { k => v, ... }
  }

=over

=item id

Entity ID, used to look up the official Entity of the area.

=item type

Copied from the Entity

=item tag_cache

Subset of the tags on the Entity object.  When tile-building is configured,
and can control which tags get cached per-tile.

=item local_path

Subset/approximation of the border path of the area which lies within the tile.

All paths are in counter-clockwise winding order, so that the area of the
entity is to the "left" of the line.

There may be multiple paths, because the path of the entity might snake back
and forth across the boundary of the tile.  If there are not any paths, it
means the tile is contained within the entity.

The path may be an abbreviated form of the actual path, for wide-area tiles.

=back

=head2 routes

Array of routes within or passing through the tile.  Each route is a hashref
of the form:

  {
    id    => $route_id,
    type  => $taxonomy_spec,
    lanes => $n,  # negative means one-way
    local_path  => [
      [ lat,lon, lat,lon, ... ],
      ...
    ],
    tag_cache => { k => v, ... },
  }

=over

=item id

Entity ID, used to look up the official Entity of the route.

=item type

Copied from the entity

=item lanes

The absolute value of this number is the number of lanes.  If negative, it
means the road is one-way.

=item local_path

Subset/approximation of the route's path which lies within the tile.

If the route has a direction, the points of the path will be in the forward
direction along the route.

=item tag_cache

Subset of the tags on the Entity object.  When tile-building is configured,
and can control which tags get cached per-tile.

=back

=back
