use FindBin;
use lib "$FindBin::Bin/lib";
use TestGeoDB ':all';
use Geo::SpatialDB;
use Geo::SpatialDB::Export::MapPolygon3D;

my $sdb= new_geodb_in_memory(
	# TODO: Add entities
);
my $ex= Geo::SpatialDB::Export::MapPolygon3D->new(
	spatial_db => $sdb,
);

subtest latlon_to_xyz => \&test_latlon_to_xyz;
sub test_latlon_to_xyz {
	my $ll2xyz= $ex->_latlon_to_xyz_coderef;
	my @tests= (
		[ [  0,  0], [ 1, 0, 0] ],
		[ [ 90,  0], [ 0, 0, 1] ],
		[ [-90,  0], [ 0, 0,-1] ],
		[ [ 90,180], [ 0, 0, 1] ],
		[ [-90,180], [ 0, 0,-1] ],
		[ [  0, 90], [ 0, 1, 0] ],
		[ [  0,-90], [ 0,-1, 0] ],
		[ [  0,180], [-1, 0, 0] ],
	);
	for (@tests) {
		my ($latlon, $xyz)= @$_;
		my $name= sprintf '(%3d,%3d)', @$latlon;
		is_within( [ $ll2xyz->(@$latlon) ], $xyz, .000000001, $name );
	}
	done_testing;
}

subtest clip_plane_normals => \&test_clip_plane_normals;
sub test_clip_plane_normals {
	# For two lat,lon coordinates, test whether they create the expected Normal vector of the plane that
	# passes through them and the origin.  The vector points toward the "inside" of the space, and the
	# "left" of the line segment from first polar coordinate to second polar coordinate, consistent
	# with counter-clockwise winding order.
	my @tests= (
		[ [  0,  0,  0, 50 ], [  0,  0,  1 ] ],
		[ [  0, 50,  0,  0 ], [  0,  0, -1 ] ],
		[ [  0,  0, 90,  0 ], [  0, -1,  0 ] ],
	);
	for (@tests) {
		my ($latlon, $xyz)= @$_;
		my $name= sprintf '(%d, %d, %d, %d)', @$latlon;
		is_within( [ $ex->_geo_plane_normal(@$latlon) ], $xyz, .000000001, $name );
	}
	
	done_testing;
}

subtest clip_plane_from_bbox => \&test_clip_plane_from_bbox;
sub test_clip_plane_from_bbox {
	my @tests= (
		[ 'Positive quadrant',
			[ 0,0, 90,90 ],
			[ 0, 1, 0 ], # west
			[ 1, 0, 0 ], # east
			[ 0, 0, 1 ], # south
			[ 0, 0, 0 ], # north is a point, so no plane
		],
	);
	for (@tests) {
		my ($name, $bbox, @expected_planes)= @$_;
		my @planes= $ex->_bbox_to_planes($bbox);
		for (0..3) {
			is_within( $planes[$_], $expected_planes[$_], 0.000000001, "$name - $_" );
		}
	}
	
	done_testing;
}

subtest clip_line_segments => \&test_clip_line_segments;
sub test_clip_line_segments {
	# Now test the code that clips lines against a set of planes
	my @tests= (
		[ 'clip diagonal at origin',
			[ (-1,-1,-1), (1,1,1) ], [ 0,0, 90,90 ], [ (0,0,0), (1,1,1) ] ],
		[ 'clip with odd lengths',
			[ (-.2,-.2,-.2), (7,7,7) ], [ 0,0, 90,90 ], [ (0,0,0), (7,7,7) ] ],
		[ 'clip both ends',
			[ (-1, 2, 1), (2,-1,1) ], [ 0,0, 90,90 ], [ (0,1,1), (1,0,1) ] ],
		[ 'excluded',
			[ (-1, 2, 1), (-.1,0,0) ], [ 0,0, 90,90 ], [] ],
	);
	for (@tests) {
		my ($name, $line, $bbox, $clipped_line)= @$_;
		my @planes= $ex->_bbox_to_planes($bbox);
		my $clipped= $ex->_clip_line_segments([$line], \@planes);
		is_within( (@$clipped? $clipped->[0] : []), $clipped_line, .000000001, $name );
	}
	
	done_testing;
}

subtest clip_triangle_to_plane => \&test_clip_triangle_to_plane;
sub test_clip_triangle_to_plane {
	my @tests= (
		[ 'inside',
			[ [ 1, 1, 1, 1, 1 ], [ 1, 0, 0, 1, 0 ], [ 1, 0, 1, 0, 1 ] ],
			[ 1, 0, 0 ],
			[ [ 1, 1, 1, 1, 1 ], [ 1, 0, 0, 1, 0 ], [ 1, 0, 1, 0, 1 ] ],
		],
		[ 'outside',
			[ [ 1, 1, 1, 1, 1 ], [ 1, 0, 0, 1, 0 ], [ 1, 0, 1, 0, 1 ] ],
			[ -1, 0, 0 ],
			()
		],
		[ 'point-on-plane',
			[ [ 0, 1, 0, 0, 0 ], [ 1, 1, 0, 0, 1 ], [ 0.1, 0, 0, 0, 0, ] ],
			[ 1, 0, 0 ],
			[ [ 0, 1, 0, 0, 0 ], [ 1, 1, 0, 0, 1 ], [ 0.1, 0, 0, 0, 0, ] ],
		],
		[ 'two-points-on-plane-outside',
			[ [ 0, 1, 0, 0, 0 ], [ 1, 1, 0, 0, 1 ], [ 0, 0, 0, 0, 0, ] ],
			[ -1, 0, 0 ],
			()
		],
		[ 'two-points-outside',
			[ [ -1, -1, 0, 0, 0 ], [ 0, 1, 0, .5, 1 ], [ 1, -1, 0, 1, 0 ] ],
			[ 0, 1, 0 ],
			[ [ -.5, 0, 0, .25, .5 ], [ 0, 1, 0, .5, 1 ], [ .5, 0, 0, .75, .5 ] ],
		],
		[ 'one-point-outside',
			[ [ -1, 1, 0, 0, 1 ], [ 0, -1, 0, .5, 0 ], [ 1, 1, 0, 1, 1 ] ],
			[ 0, 1, 0 ],
			[ [ -1, 1, 0, 0, 1 ], [ -.5, 0, 0, .25, .5 ], [ .5, 0, 0, .75, .5 ] ],
			[ [ 0.5, 0, 0, .75, .5 ], [ 1, 1, 0, 1, 1 ], [ -1, 1, 0, 0, 1 ] ],
		]
	);
	for (@tests) {
		my ($name, $triangle, $plane, @expected)= @$_;
		try {
			my @result= $ex->_clip_triangle_to_plane($triangle, $plane);
			is_deeply( \@result, \@expected, $name )
				or diag explain(\@expected), explain(\@result);
		} catch {
			diag $_;
			false( $name );
		};
	}
}

#subtest path_to_xyz => \&test_path_to_xyz;
sub test_path_to_xyz {
	my $rseg= Geo::SpatialDB::RouteSegment->new(
		id => 'foo',
		path => [ [ 40.01, 70.01 ], [ 40.02, 70.02 ] ]
	);
	my $paths= $ex->generate_route_lines({ entities => { foo => $rseg } });
	is( $#$paths, 0, 'one path' );
	is( $#{ $paths->[0][1] }, 1, 'two verticies' );
	is_within(
		$paths->[0][1],
		[
			[ 0.261838633349351, 0.719786587993401, 0.642921299873136 ],
			[ 0.261674657326358, 0.719726808351777, 0.64305497047523 ],
		],
		.000000001,
		'vertex values',
	);
};

#subtest path_to_polygons => \&test_path_to_polygons;
sub test_path_to_polygons {
	my $rseg= Geo::SpatialDB::RouteSegment->new(
		id => 'foo',
		path => [ [ 40.01, 70.01 ], [ 40.02, 70.02 ] ]
	);
	my $polys= $ex->generate_route_polygons({ entities => { foo => $rseg } }, road_width => .000001);
	is( $#$polys, 0, 'one path' );
	is( $#{ $polys->[0][1] }, 3, 'four verticies' );
	is_within(
		$polys->[0][1],
		[
			[ 0.261839245831099, 0.719785949238465, 0.642921765553541 ],
			[ 0.261838020867602, 0.719787226748336, 0.64292083419273  ],
			[ 0.261675269808106, 0.719726169596841, 0.643055436155635 ],
			[ 0.261674044844609, 0.719727447106712, 0.643054504794824 ]
		],
		.000000001,
		'vertex values'
	);
};

undef $ex; undef $sdb;

done_testing;
