package Geo::SpatialDB::Entity::RouteSegment;
use Moo 2;
use Carp;
use Geo::SpatialDB::Math 'llbox', 'vector_latlon';
use namespace::clean;

# ABSTRACT: A piece of a Route, represented by a contiguous sequence of points
# VERSION

extends 'Geo::SpatialDB::Entity';

=head1 DESCRIPTION

These entities, in addition to the rest of the Entity API, also provide a
directed graph for navigation purposes.

=head2 routes

The logical route entities which share this segment.

=head2 provides

Describes every navigable portion of this route, such as bike lane, car lane, waterway, etc.
The data in this should provide low-level details that generic attributes like 'lanes' and
'speed' can't accurately contain.  This feature needs better specificaton.

=head2 latlon_seq

An arrayref plotting the C<< (lat,lon) >> coordinates of the route.

=head2 twoway

Whether the route can be traversed in the opposite direction.

=head2 lanes

Number of lanes (for cars, or whatever vehicle is appropriate for this route).
Simplification of the data found in L</provides>.

=head2 speed

The generic concept of speed limit for this route segment.
Simplification of the data found in L</provides>.

=head2 endpoint0

The unique ID of the starting endpoint.

=head2 endpoint1

The unique ID of the destination endpoint.

=head2 path_ids

A list of paths which compose this route.  This is an implementation detail;
normal users should be using L<laton_seq>.

=cut

has path_ids       => ( is => 'rw' );
has latlon_seq_cb  => ( is => 'rw' );
has twoway         => ( is => 'rw' );
has lanes          => ( is => 'rw' );
has speed          => ( is => 'rw' );
has restrictions   => ( is => 'rw' );
has routes         => ( is => 'rw' );

has latlon_seq     => ( is => 'lazy' );
sub latlon_seq_pts {
	my $seq= shift->latlon_seq;
	[ map vector_latlon($seq->[$_*2], $seq->[$_*2+1]), 0..(@$seq/2)-1 ]
}

has endpoint0      => ( is => 'lazy' );
has endpoint1      => ( is => 'lazy' );

sub _build_latlon_seq {
	my $callback= $_[0]->_latlon_seq_cb // croak "No latlon_seq and no generator callback for RouteSegment ".$_[0]->id;
	$callback->($_[0])
}
sub _build_endpoint0 { sprintf '%.6lf,%.6lf', @{$_[0]->latlon_seq}[0,1] }
sub _build_endpoint1 { sprintf '%.6lf,%.6lf', @{$_[0]->latlon_seq}[-2,-1] }

=head1 METHODS

=head2 features_at_resolution

See L<Geo::SpatialDB::Entity/features_at_resolution>

This implementation walks the L</path> and generates a feature at every
C<$resolution * 2> degrees latitude.

=cut

sub features_at_resolution {
	my ($self, $resolution)= @_;
	# I lied.   Just return every point along the path with a radius
	# of the distance to the next/previous point.
	# TODO: actually implement algorithm of following the path.
	my @ret;
	my $ll_seq= $self->latlon_seq;
	for (my $i= 1; $i < @$ll_seq/2; $i++) {
		push @ret, llbox( @{$ll_seq}[$i-2 .. $i+1] );
	}
	\@ret;
}

1;
