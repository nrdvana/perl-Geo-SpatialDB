package Geo::SpatialDB::TileMapper::Rect;
use Moo 2;
with 'Geo::SpatialDB::TileMapper';

# ABSTRACT: Divide the globe into lat/lon rectangles
# VERSION

=head1 DESCRIPTION

This L<TileMapper|Geo::SpatialDB::TileMapper> uses very simple math of dividing
the globe into some number of latitude divisions and longitude divisions, forming
"rectangular" tiles.

=head1 ATTRIBUTES

=head2 lat_divs

Number of divisions of latitude (out of 180 degrees)

=head2 lon_divs

Number of longitude divisions (out of 360 degrees)

=cut

has lat_divs   => ( is => 'ro', required => 1 );
has lon_divs   => ( is => 'ro', required => 1 );

=head1 METHODS

See L<TileMapper|Geo::SpatialDB::TileMapper> for:

=over

=item L<tiles_in|Geo::SpatialDB::TileMapper/tiles_in>

=item L<tile_at|Geo::SpatialDB::TileMapper/tile_at>

=item L<tile_polygon|Geo::SpatialDB::TileMapper/tile_polygon>

=back

=cut

sub tiles_in {
	my ($self, $llarea)= @_;
	return $self->_tiles_in_range(@{ $llarea->as_llbox });
}

sub _tiles_in_range {
	my ($self, $lat0, $lon0, $lat1, $lon1)= @_;
	my ($lat_divs, $lon_divs)= ($self->lat_divs, $self->lon_divs);
	# clamp latitude
	$lat0=  90 if $lat0 >  90;
	$lat0= -90 if $lat0 < -90;
	my $lat_idx0= int((90-$lat0) * $lat_divs / 180);
	my $lon_idx0= $lon0/360 * $lon_divs;
	$lon_idx0+= $lon_divs*(1+ int(-$lon_idx0/$lon_divs)) if $lon_idx0 < 0;
	$lon_idx0= $lon_idx0 % $lon_divs;
	return $lat_idx0 * $lon_divs + $lon_idx0
		if @_ == 3;
	# clamp end lat
	$lat1=  90 if $lat1 >  90;
	$lat1= -90 if $lat1 < -90;
	my $lat_idx1= int((90-$lat1) * $lat_divs / 180);
	my $lon_idx1= $lon1/360 * $lon_divs;
	$lon_idx1+= $lon_divs*(1+ int(-$lon_idx1/$lon_divs)) if $lon_idx1 < 0;
	$lon_idx1= $lon_idx1 % $lon_divs;
	# longitude might wrap globe, or be single point.
	# If lon end tile same as lon start tile, determine
	# full circle vs. single tile based on $lon1 < $lon0
	$lon_idx1-- if $lon_idx1 == $lon_idx0 and $lon1 < $lon0; # cause a wrap if caller requested full-globe
	# need to wrap
	$lon_idx1+= $lon_divs if $lon_idx1 < $lon_idx0;
	my @ids;
	for my $lat ($lat_idx1 .. $lat_idx0) {
		for my $lon ($lon_idx0 .. $lon_idx1) {
			push @ids, $lat * $lon_divs + ($lon % $lon_divs);
		}
	}
	return \@ids;
}

sub tile_at {
	my ($self, $lat, $lon)= @_;
	return $self->_tiles_in_range($lat, $lon);
}

sub tile_polygon {
	my ($self, $tile_id)= @_;
	my ($lat_divs, $lon_divs)= ($self->lat_divs, $self->lon_divs);
	my ($lat_idx, $lon_idx);
	{ use integer;
		($lat_idx, $lon_idx)= ($tile_id / $lon_divs, $tile_id % $lon_divs)
	}
	my $lat1= 90 - $lat_idx/$lat_divs*180;
	my $lon0= $lon_idx/$lon_divs*360;
	my $lat0= 90 - ($lat_idx+1)/$lat_divs*180;
	my $lon1= ($lon_idx+1)/$lon_divs*360;
	$lon0 -= 360 if $lon0 >= 180;
	$lon1 -= 360 if $lon1 >= 180;
	return [$lat1,$lon0,  $lat0,$lon0,  $lat0,$lon1,  $lat1,$lon1];
}

1;
