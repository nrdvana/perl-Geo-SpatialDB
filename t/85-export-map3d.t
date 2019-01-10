use FindBin;
use lib "$FindBin::Bin/lib";
use TestGeoDB ':all';
use Geo::SpatialDB;
use Geo::SpatialDB::RouteSegment;
use Geo::SpatialDB::Path;
use Geo::SpatialDB::Export::MapPolygon3D;
use Geo::SpatialDB::Export::MapPolygon3D::Vector qw/ vector vector_latlon /;
use Geo::SpatialDB::Export::MapPolygon3D::Polygon 'polygon';
my $sdb= Geo::SpatialDB->new(storage => { CLASS => 'Memory' });
my $map3d= Geo::SpatialDB::Export::MapPolygon3D->new(spatial_db => $sdb);

subtest latlon_to_xyz => \&test_latlon_to_xyz;
sub test_latlon_to_xyz {
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
		is_within( [ vector_latlon(@$latlon)->xyz ], $xyz, .000000001, $name );
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
		my @planes= $map3d->_bbox_to_clip_planes($bbox);
		is_within( \@planes, \@expected_planes, 0.000000001, $name );
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
		my @planes= $map3d->_bbox_to_clip_planes($bbox);
		my $clipped= $map3d->_clip_line_segments([$line], \@planes);
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
			[ [ -1, 1, 0, 0, 1 ], [ 0.5, 0, 0, .75, .5 ], [ 1, 1, 0, 1, 1 ] ],
		]
	);
	for (@tests) {
		my ($name, $triangle, $plane, @expected)= @$_;
		$triangle= polygon(map vector(@$_), @$triangle);
		$plane= vector(@$plane);
		try {
			$triangle->clip_to_planes($plane);
			is_deeply( [ $triangle->as_triangles ], \@expected, $name )
				or diag explain(\@expected), explain($triangle);
		} catch {
			diag $_;
			false( $name );
		};
	}
}

subtest path_to_xyz => \&test_path_to_xyz;
sub test_path_to_xyz {
	my $rseg= Geo::SpatialDB::RouteSegment->new(
		id => 'foo',
		path => [ [ 40.01, 70.01 ], [ 40.02, 70.02 ] ]
	);
	my $paths= $map3d->generate_route_lines({ entities => { foo => $rseg } });
	is( scalar @$paths, 1, 'one path' );
	is( scalar @{ $paths->[0]{line_strip} }, 2, 'two verticies' ) or diag explain $paths;
	is_within(
		$paths->[0]{line_strip},
		[
			[ 0.261838633349351, 0.719786587993401, 0.642921299873136 ],
			[ 0.261674657326358, 0.719726808351777, 0.64305497047523 ],
		],
		.000000001,
		'vertex values',
	) or diag explain $paths;
}

subtest path_to_polygons => \&test_path_to_polygons;
sub test_path_to_polygons {
	my $lw= $map3d->lane_width/$map3d->earth_radius; # lane-width
	my @tests= (
		[ 'single path segment',
			[ [ 0,0 ], [ 0,0.000100 ] ],
			[[
				[ 1, 0, $lw, 0, 0 ],
				[ 1, 0, -$lw, 1, 0 ],
				vector_latlon(0, 0.0001)->add([ 0, 0,-$lw ])->set_st(1,3.70649755),
				vector_latlon(0, 0.0001)->add([ 0, 0, $lw ])->set_st(0,3.70649755),
			]]
		],
		[ 'single path segment reversed',
			[ [ 0,0.000100 ], [ 0,0 ] ],
			[[
				vector_latlon(0, 0.0001)->add([ 0, 0,-$lw ])->set_st(0,0),
				vector_latlon(0, 0.0001)->add([ 0, 0, $lw ])->set_st(1,0),
				[ 1, 0, $lw, 1, 3.70649755 ],
				[ 1, 0, -$lw, 0, 3.70649755 ],
			]]
		],
		[ '90 degree elbow',
			[ [ 0,0 ], [ 0,0.000100 ], [0.000100,0.000100] ],
			[[
				vector_latlon(0, 0.0001)->add([ 0, -$lw, $lw ])->set_st(0,2.70649755),
				[ 1, 0, $lw, 0, 0 ],
				[ 1, 0, -$lw, 1, 0 ],
				vector_latlon(0, 0.0001)->add([ 0,  $lw,-$lw ])->set_st(1,4.70649755),
			],[
				vector_latlon(0, 0.0001)->add([ 0, -$lw, $lw ])->set_st(0,4.70649755),
				vector_latlon(0, 0.0001)->add([ 0,  $lw,-$lw ])->set_st(1,2.70649755),
				vector_latlon(0.0001, 0.0001)->add([ 0,  $lw, 0 ])->set_st(1,7.41299511),
				vector_latlon(0.0001, 0.0001)->add([ 0, -$lw, 0 ])->set_st(0,7.41299511),
			]]
		],
	);
	for (@tests) {
		my ($name, $path, $expected)= @$_;
		my @vecpath= map vector_latlon(@$_), @$path;
		my $polys= $map3d->_generate_polygons_for_path(\@vecpath, undef, { width => $lw*2 }, {}, undef);
		is( scalar @$polys, scalar @$expected, "$name - polygon count = ".scalar(@$expected) );
		is_within( $polys, $expected, 0.00000001, "$name - polygons" )
			or diag explain $polys;
	}
}

undef $map3d; undef $sdb;

done_testing;
