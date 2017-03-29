package Geo::SpatialDB::TileMap::Rect;
use Moo;

has lat_step   => ( is => 'ro', required => 1 );
has lon_step   => ( is => 'ro', required => 1 );
has y_cnt      => ( is => 'lazy', builder => sub { use integer; my $self= shift; 2 * ((89_999_999 + $self->lat_step) / $self->lat_step); } );
has x_cnt      => ( is => 'lazy', builder => sub { use integer; my $self= shift; 2 * ((179_999_999 + $self->lon_step) / $self->lon_step); } );
has tile_count => ( is => 'lazy', builder => sub { use integer; my $self= shift; $self->y_cnt * $self->x_cnt; } );

sub get_tiles_for_rect {
	my ($self, $lat0, $lon0, $lat1, $lon1)= @_;
	use integer;
	my ($x_cnt, $lon_step, $y_cnt, $lat_step)=
		( $self->x_cnt, $self->lon_step, $self->y_cnt, $self->lat_step );
	$lon0= _wrap_lon($lon0);
	$lat0= _clamp_lat($lat0);
	my $min_x= ($lon0 + ($x_cnt/2) * $lon_step) / $lon_step;
	my $min_y= ($lat0 + ($y_cnt/2) * $lat_step) / $lat_step;
	return ($min_y % $y_cnt) * $x_cnt + ($min_x % $x_cnt)
		if @_ <= 3;
	$lon1= _wrap_lon($lon1); $lon1 += 360_000_000 if $lon1 < $lon0;
	$lat1= _clamp_lat($lat1);
	my $max_x= ($lon1 + ($x_cnt/2) * $lon_step) / $lon_step;
	my $max_y= ($lat1 + ($y_cnt/2) * $lat_step) / $lat_step;
	my @ids;
	for (my $y= $min_y; $y <= $max_y; ++$y) {
		for (my $x= $min_x; $x <= $max_x; ++$x) {
			push @ids, ($y % $y_cnt) * $x_cnt + ($x % $x_cnt);
		}
	}
	return @ids;
}

sub get_tile_at {
	return shift->get_tiles_for_rect(@_);
}

sub get_tile_polygon {
	my ($self, $tile_id)= @_;
	use integer;
	my ($y, $x)= ($tile_id / $self->x_cnt, $tile_id % $self->x_cnt);
	my $lat0= _clamp_lat(($y - $self->y_cnt/2) * $self->lat_step);
	my $lat1= _clamp_lat($lat0 + $self->lat_step);
	my $lon0= _clamp_lon(($x - $self->x_cnt/2) * $self->lon_step);
	my $lon1= _clamp_lon($lon0 + $self->lon_step);
	return ($lat0,$lon0,  $lat1,$lon0,  $lat1,$lon1,  $lat0,$lon1);
}

sub _clamp_lat {
	$_[0] < -90_000_000? -90_000_000 : $_[0] > 90_000_000? 90_000_000 : $_[0]
}
sub _clamp_lon {
	$_[0] < -180_000_000? -180_000_000 : $_[0] > 180_000_000? 180_000_000 : $_[0]
}
sub _wrap_lon {
	use integer;
	$_[0] < -180_000_000? (($_[0] - 180_000_000) % 360_000_000)+180_000_000
		: $_[0] > 180_000_000? (($_[0] + 180_000_000) % 360_000_000) - 180_000_000
		: $_[0]
}

1;
