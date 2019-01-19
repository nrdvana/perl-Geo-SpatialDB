#! /usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Geo::SpatialDB::Math 'llbox';
use_ok 'Geo::SpatialDB::TileMapper::Rect';

# This config should cause exactly 9 tiles above equator, 9 below,
# and 36 around the globe with a perfect seam at the meridian.
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
	my $pts= $tmap->tile_polygon($key);
	is_deeply( $pts, [ $lat1,$lon0,  $lat0,$lon0,  $lat0,$lon1,  $lat1,$lon1 ], "tile $key" );
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

my $set= $tmap->tiles_for_area(llbox(-1,-1,1,1));
is_deeply( [ sort { $a <=> $b } @$set ], [ 288, 323, 324, 359 ], 'select across equator meridian' );
$set= $tmap->tiles_for_area(llbox(-1,179,1,-179));
is_deeply( [ sort { $a <=> $b } @$set ], [ 8*36+17, 8*36+18, 9*36+17, 9*36+18 ], 'select across equator antimeridian' );

if ($ENV{TEST_ALL_MICRODEGREES}) {
	subtest all_microdegrees_across_antimeridian => sub {
		my $tmap2= new_ok 'Geo::SpatialDB::TileMapper::Rect', [ lat_divs => 180_000, lon_divs => 360_000 ],
			'Rect tile mapper millidegrees';
		for my $lat_md (0..100_000) {
			for my $lon_md (0..100_000) {
				my ($lat, $lon)= (-.05 + ($lat_md/1_000_000), 179.95 + ($lon_md/1_000_000));
				my $tile= $tmap->tile_at($lat, $lon);
				my $tiles= $tmap->tiles_for_area(llbox($lat - .0005, $lon - .0005, $lat + .0005, $lon + .0005));
				if (@$tiles > 4) {
					diag sprintf("More than 4 tiles found for range %.6f,%.6f %.6f,%.6f", $lat - .0005, $lon - .0005, $lat + .0005, $lon + .0005);
					fail( 'Always 4 or less tiles' );
					die;
				}
				if (!grep { $_ == $tile } @$tiles) {
					diag sprintf("Tile range %.6f,%.6f %.6f,%.6f does not include tile %d", $lat - .0005, $lon - .0005, $lat + .0005, $lon + .0005, $tile);
					fail( 'Always includes tile from center coordinates' );
					die;
				}
			}
		}
	};
}

done_testing;
