#! /usr/bin/env perl
use strict;
use warnings;
use Test::More;

use_ok 'Geo::SpatialDB::TileMapper::Rect';

# This config should cause exactly 9 tiles above equator, 9 below,
# and 36 around the globe with a perfect seam at the antimeridian.
my $tmap= new_ok 'Geo::SpatialDB::TileMapper::Rect', [ lat_divs => 18, lon_divs => 36 ],
	'Rect tilemapper';

my @tiles= (
	#           lat0,lon0,  lat1,lon1
	[    0 => [   80,   0,   90,  10  ]],
	[    1 => [   80,  10,   90,  20  ]],
	[   17 => [   80, 170,   90,-180  ]],
	[   18 => [   80,-180,   90,-170  ]],
	[   35 => [   80, -10,   90,   0  ]],
	[   36 => [   70,   0,   80,  10  ]],
	[ 8*36 => [    0,   0,   10,  10  ]],
	[ 9*36-1 => [  0, -10,   10,   0  ]],
	[ 9*36 => [  -10,   0,    0,  10  ]],
	[17*36 => [  -90,   0,  -80,  10  ]],
	[18*36-1 => [-90, -10,  -80,   0  ]],
);

for my $test (@tiles) {
	my ($key, $latlon)= @$test;
	my ($lat0, $lon0, $lat1, $lon1)= @$latlon;
	my @pts= $tmap->tile_polygon($key);
	is_deeply( \@pts, [ $lat1,$lon0,  $lat0,$lon0,  $lat0,$lon1,  $lat1,$lon1 ], "tile $key" );
}

for my $test (@tiles) {
	my ($key, $latlon)= @$test;
	my ($lat0, $lon0, $lat1, $lon1)= @$latlon;
	is( $tmap->tile_at( $lat1,          $lon0            ), $key, "top left of tile $key" );
	is( $tmap->tile_at( $lat1-0.000001, $lon0+0.000001   ), $key, "inside top left of tile $key" );
	is( $tmap->tile_at( $lat0+0.000001, $lon1-0.000001   ), $key, "inside bottom right of tile $key" );
	is( $tmap->tile_at( $lat1-0.000001, $lon1-0.000001   ), $key, "inside top right of tile $key" );
	is( $tmap->tile_at( $lat0+0.000001, $lon0+0.000001   ), $key, "inside bottom left of tile $key" );
	isnt( $tmap->tile_at( $lat1, $lon1 ), $key, "bottom-left goes to new tile" );
	is( $tmap->tile_at( $lat1, $lon0+360 ), $key, "wrap lon+360 tile $key" );
	is( $tmap->tile_at( $lat1, $lon0-360 ), $key, "wrap lon-360 tile $key" );
}

my @set= $tmap->tiles_in_range(-1,-1,1,1);
is_deeply( [ sort { $a <=> $b } @set ], [ 288, 323, 324, 359 ], 'select across equator meridian' );
@set= $tmap->tiles_in_range(-1,179,1,-179);
is_deeply( [ sort { $a <=> $b } @set ], [ 8*36+17, 8*36+18, 9*36+17, 9*36+18 ], 'select across equator antimeridian' );

done_testing;
