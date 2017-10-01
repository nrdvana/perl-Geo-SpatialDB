package Geo::SpatialDB::TileMapper::Rect;
use Moo 2;

has lat_divs   => ( is => 'ro', required => 1 );
has lon_divs   => ( is => 'ro', required => 1 );

sub tiles_in_range {
	my ($self, $lat0, $lon0, $lat1, $lon1)= @_;
	my ($lat_divs, $lon_divs)= ($self->lat_divs, $self->lon_divs);
	# clamp latitude
	$lat0= -0x10000000 if $lat0 < -0x10000000;
	$lat0=  0x10000000 if $lat0 >  0x10000000;
	# wrap longitude, and shift so any partial div is opposite prime meridian
	$lon0= ($lon0 + 0x20000000) & 0x3FFFFFFF;
	my $lat_idx= int(($lat0+0x10000000) * $lat_divs / 2**29);
	my $lon_idx= int($lon0 * $lon_divs / 2**30);
	return $lat_idx * $lon_divs + $lon_idx
		if @_ <= 3;
	# clamp end lat
	$lat1= -0x10000000 if $lat1 < -0x10000000;
	$lat1=  0x10000000 if $lat1 >  0x10000000;
	# wrap end longitude, and shift so any partial div is opposite prime meridian
	$lon1= ($lon1 + 0x20000000) & 0x3FFFFFFF;
	# latitude span is positive or zero
	my $lat_idx_end= int(($lat1 + 0x10000000) * $lat_divs / 2**29);
	# longitude might wrap globe, or be single point.
	# If lon end tile same as lon start tile, determine
	# full circle vs. single tile based on $lon1 < $lon0
	my $lon_idx_end= int($lon1 * $lon_divs / 2**30);
	$lon_idx_end-- if $lon_idx_end == $lon_idx?
		$lon1 < $lon0 # cause a wrap if caller requested full-globe
		: int($lon_idx_end * 2**30 / $lon_divs) == $lon1; # don't include end just because boundary touched
	# need to wrap
	$lon_idx_end+= $lon_divs if $lon_idx_end < $lon_idx;
	my @ids;
	for my $lat ($lat_idx .. $lat_idx_end) {
		for my $lon ($lon_idx .. $lon_idx_end) {
			push @ids, $lat * $lon_divs + ($lon % $lon_divs);
		}
	}
	return @ids;
}

sub tile_at {
	return shift->get_tiles_in_range(@_);
}

sub tile_polygon {
	my ($self, $tile_id)= @_;
	my ($lat_divs, $lon_divs)= ($self->lat_divs, $self->lon_divs);
	my ($lat_idx, $lon_idx);
	{ use integer;
		($lat_idx, $lon_idx)= ($tile_id / $lon_divs, $tile_id % $lon_divs)
	}
	print STDERR "lat_idx=$lat_idx, lon_idx=$lon_idx\n";
	my $lat0= int($lat_idx * 2**29 / $lat_divs) - 0x10000000;
	my $lon0= int($lon_idx * 2**30 / $lon_divs) - 0x20000000;
	my $lat1= int(($lat_idx+1) * 2**29 / $lat_divs) - 0x10000000;
	my $lon1= (int(($lon_idx+1) * 2**30 / $lon_divs) & 0x3FFFFFFF) - 0x20000000;
	$lat1= 0x20000000 if $lat1 > 0x20000000;
	return ($lat0,$lon0,  $lat0,$lon1,  $lat1,$lon1,  $lat1,$lon0);
}

1;
