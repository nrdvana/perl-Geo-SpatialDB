package Geo::SpatialDB::Path;
use Moo 2;
use namespace::clean;

# ABSTRACT: A connected sequence of points on the map
# VERSION

=head1 ATTRIBUTES

=head2 id

A unique ID for this path.

=head2 seq

The sequence of C<< ($lat,$lon) >> coordinates that makes up the path.
This is a single arrayref of pairs of values.

=cut

has id  => ( is => 'rw' );
has seq => ( is => 'rw' );

1;
