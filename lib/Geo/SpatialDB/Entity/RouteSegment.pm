package Geo::SpatialDB::Entity::RouteSegment;

use Moo 2;
use namespace::clean;

# ABSTRACT: A piece of a Route, represented by a contiguous sequence of points

extends 'Geo::SpatialDB::Entity';

=head1 DESCRIPTION

These entities, in addition to the rest of the Entity API, also provide a
directed graph for navigation purposes.

=head2 path

=head2 oneway

=head2 lanes

=head2 speed

=head2 routes

=cut

has path       => ( is => 'rw' );
has oneway     => ( is => 'rw' );
has lanes      => ( is => 'rw' );
has min_speed  => ( is => 'rw' );
has routes     => ( is => 'rw' );
has endpoint0  => ( is => 'rw' );
has endpoint1  => ( is => 'rw' );

=head1 METHODS

=head2 features_at_resolution

See L<Geo::SpatialDB::Entity/features_at_resolution>

This implementation walks the L</path> and generates a feature at every
C<$resolution * 2> degrees latitude.

=cut

sub features_at_resolution {
	my $resolution= shift;
	# I lied.   Just return every point along the path with a radius
	# of the distance to the next/previous point.
	# TODO: actually implement algorithm of following the path.
	my $prev= $self->path->[1];
	return map {
		my %f;
		if ($prev) {
			my ($lat0, $lat1)= sort { $a <=> $b } ($prev->{lat}, $_->{lat});
			my ($lon0, $lon1)= sort { $a <=> $b } ($prev->{lon}, $_->{lon});
			@f{'lat0','lon0','lat1','lon1'}= ($lat0, $lon0, $lat1, $lon1);
		}
		$prev= $_;
		$prev? (\%f) : ()
	} @{ $self->path };
}

1;
