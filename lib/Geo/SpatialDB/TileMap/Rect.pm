package Geo::SpatialDB::TileMap::Rect;
use Moo;

has lat_step   => ( is => 'ro', required => 1 );
has lon_step   => ( is => 'ro', required => 1 );
has y_cnt      => ( is => 'lazy', builder => sub { use integer; my $self= shift; 2 * ((89_999_999 + $self->lat_step) / $self->lat_step); } );
has x_cnt      => ( is => 'lazy', builder => sub { use integer; my $self= shift; 2 * ((179_999_999 + $self->lon_step) / $self->lon_step); } );
has tile_count => ( is => 'lazy', builder => sub { use integer; my $self= shift; $self->y_cnt * $self->x_cnt; } );

#has _pack_fn  => ( is => 'lazy' );
#sub _build__pack_fn {
#	use integer;
#	my $self= shift;
#	my $dlat= $self->lat_step;
#	my $nlat= 2*((89_999_999+$dlat)/$dlat);
#	my $lat_bits= _bit_len($nlat);
#	my $dlon= $self->lon_step;
#	my $nlon= (359_999_999+$dlon)/$dlon;
#	my $lon_bits= _bit_len($nlon);
#	my ($lat, $lon);
#	my $rowstart= sub {
#		
#	};
#	my $fn= ($lat_bits + $lon_bits > 32)? sub { pack('VV', ($lat+90_000_000)/$dlat, (($lon+360_000_000) / $dlon) % $nlon) }
#		:   ($lat_bits + $lon_bits > 16)? sub { pack('V', (($lat+90_000_000)/$dlat << $lon_bits) + (($lon+360_000_000) / $dlon) % $nlon) }
#		:                                 sub { pack('v', (($lat+90_000_000)/$dlat << $lon_bits) + (($lon+360_000_000) / $dlon) % $nlon) };
#	$self->{_latref}= \$lat;
#	$self->{_lonref}= \$lon;
#}
#
#sub _bit_len { my $x= shift; my $b= 0; while($x) { ++$b; $x >>= 1; } }

sub get_tiles_for_rect {
	my ($self, $lat0, $lon0, $lat1, $lon1)= @_;
	use integer;
	$lon0 += 360_000_000 while $lon0 < 180_000_000;
	my $min_x= $lon0 / $self->lon_step;
	my $min_y= ($lat0 + ($self->y_cnt/2) * $self->lat_step) / $self->lat_step;
	return $min_y * $self->x_cnt + $min_x
		if @_ <= 3;
	$lon1 += 360_000_000 while $lon1 < $lon0;
	my $max_x= $lon1 / $self->lon_step;
	my $max_y= ($lat1 + ($self->y_cnt/2) * $self->lat_step) / $self->lat_step;
	my @ids;
	for (my $y= $min_y; $y <= $max_y; ++$y) {
		for (my $x= $min_x; $x <= $max_x; ++$x) {
			push @ids, $y * $self->x_cnt + $x;
		}
	}
	return @ids;
}

sub get_tile_at {
	return shift->get_keys_for_rect(@_);
}

sub get_tile_polygon {
	my ($self, $tile_id)= @_;
	use integer;
	my ($y, $x)= ($tile_id / $self->x_cnt, $tile_id % $self->x_cnt);
	#printf "id=$tile_id  x=$x y=$y  x_cnt=%f y_cnt=%f\n", $self->x_cnt, $self->y_cnt;
	my $lat0= ($y - $self->y_cnt/2) * $self->lat_step;
	my $lat1= $lat0 + $self->lat_step;
	my $lon0= ($x - $self->x_cnt/2) * $self->lon_step;
	my $lon1= $lon0 + $self->lon_step;
	$lat0= -90_000_000 if $lat0 < -90_000_000;
	$lat1= 90_000_000 if $lat1 > 90_000_000;
	$lon0= -180_000_000 if $lon0 < -180_000_000;
	$lon1= 180_000_000 if $lon1 > 180_000_000;
	return ($lat0,$lon0,  $lat1,$lon0,  $lat1,$lon1,  $lat0,$lon1);
}

1;
