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
	#          lat0,lon0,  lat1,lon1
	[   0 => [  -90,-180,  -80,-170  ]],
	[   1 => [  -90,-170,  -80,-160  ]],
	[  35 => [  -90, 170,  -80, 180  ]],
	[  36 => [  -80,-180,  -70,-170  ]],
	[ 288 => [  -10,-180,    0,-170  ]],
	[ 323 => [  -10, 170,    0, 180  ]],
	[ 324 => [    0,-180,   10,-170  ]],
	[ 359 => [    0, 170,   10, 180  ]],
	[ 629 => [   80, -10,   90,   0  ]],
    [ 630 => [   80,   0,   90,  10  ]],
	[ 647 => [   80, 170,   90, 180  ]],
);
sub deg_to_32c { (int(($_ * 2**31)/360 + 1)>>1)&0x3FFFFFFF }

for my $test (@tiles) {
	my ($key, $latlon)= @$test;
	my ($lat0, $lon0, $lat1, $lon1)= map deg_to_32c($_), @$latlon;
	my @pts= $tmap->tile_polygon($key);
	is_deeply( \@pts, [ $lat0,$lon0,  $lat0,$lon1,  $lat1,$lon1,  $lat1,$lon0 ], "tile $key" );
}

for my $test (@tiles) {
	my ($key, $latlon)= @$test;
	my ($lat0, $lon0, $lat1, $lon1)= map deg_to_32c($_), @$latlon;
	is( $tmap->get_tile_at( $lat0+1, $lon0-0x3FFFFFFF ), $key, "bottomleft of tile $key" );
	is( $tmap->get_tile_at( $lat0+1, $lon0+1          ), $key, "wrap -lon tile $key" );
	is( $tmap->get_tile_at( $lat0+1, $lon0+0x40000001 ), $key, "wrap +lon tile $key" );
}

my @set= $tmap->tiles_for_rect(-1, 0x3FFFFFFF, 1, 0x40000000);
is_deeply( [ sort { $a <=> $b } @set ], [ 288, 323, 324, 359 ], 'select across equator dateline' );

done_testing;
