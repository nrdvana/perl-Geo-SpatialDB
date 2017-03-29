#! /usr/bin/env perl
use strict;
use warnings;
use Test::More;

use_ok 'Geo::SpatialDB::TileMap::Rect';
my $tmap= new_ok 'Geo::SpatialDB::TileMap::Rect', [ lat_step => 10_000_000, lon_step => 10_000_000 ],
	'Rect tilemap';

is( $tmap->tile_count, 36*18, 'tile_count' );

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

for my $test (@tiles) {
	my ($key, $latlon)= @$test;
	my ($lat0, $lon0, $lat1, $lon1)= map { $_*1_000_000 } @$latlon;
	my @pts= $tmap->get_tile_polygon($key);
	is_deeply( \@pts, [ $lat0,$lon0,  $lat1,$lon0,  $lat1,$lon1,  $lat0,$lon1 ], "tile $key" );
}

for my $test (@tiles) {
	my ($key, $latlon)= @$test;
	my ($lat0, $lon0, $lat1, $lon1)= map { $_*1_000_000 } @$latlon;
	is( $tmap->get_tile_at( $lat0+1, $lon0-359_999_999 ), $key, "bottomleft of tile $key" );
	is( $tmap->get_tile_at( $lat0+1, $lon0+1           ), $key, "wrap -lon tile $key" );
	is( $tmap->get_tile_at( $lat0+1, $lon0+360_000_001 ), $key, "wrap +lon tile $key" );
}

my @set= $tmap->get_tiles_for_rect(-9, -189_000_000, 9, -179_000_000);
is_deeply( [ sort { $a <=> $b } @set ], [ 288, 323, 324, 359 ], 'select across equator dateline' );

done_testing;
