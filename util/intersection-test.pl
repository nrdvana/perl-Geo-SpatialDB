#! /usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use OpenGL::Sandbox qw( -V1 :all glLoadIdentity GL_LINES GL_LINE_STRIP GL_LINE_LOOP );
use Math::Trig qw( deg2rad );
use Geo::SpatialDB;
use Geo::SpatialDB::RouteSegment;
use Geo::SpatialDB::Path;
use Geo::SpatialDB::Export::MapPolygon3D;
use Geo::SpatialDB::Export::MapPolygon3D::Vector 'vector_latlon';
my $sdb= Geo::SpatialDB->new(storage => { CLASS => 'Memory' }, latlon_scale => 1);
my $map3d= Geo::SpatialDB::Export::MapPolygon3D->new(spatial_db => $sdb);

sub sin360 { sin(deg2rad(shift)) }
sub cos360 { cos(deg2rad(shift)) }
sub meter_arc() { 360 / 40075000; } # a meter of earth's surface, in degrees

my $v2_angle= 0;
my @segments= (
	Geo::SpatialDB::RouteSegment->new(
		path => Geo::SpatialDB::Path->new(id => 1, seq => [ [meter_arc*100,0], [0,0], [0,0] ]),
		lanes => 2,
	),
	Geo::SpatialDB::RouteSegment->new(
		path => Geo::SpatialDB::Path->new(id => 2, seq => [ [0,0], [0,0] ]),
		lanes => 2,
	),
);

make_context;
setup_projection( top => .000005, bottom => -.000005, ortho => 1, near => -1, far => 1, z => 0);
while (1) {
	next_frame;
	#trans 0,0,-1.5;
	rotate x => -90;
	rotate z => 90;
	#scale 1, 1, 1;
	globe();
	$v2_angle -= 20/60; # degrees per 1/60 second
	my @pt1= (  # 100 meter road, rotated around the intersection
		cos360($v2_angle) * 20 * meter_arc,
		sin360($v2_angle) * 20 * meter_arc
	);
	@{ $segments[1]->path->seq->[0] }= @{ $segments[0]->path->seq->[-1] }= @pt1;
	my @pt2= (
		$pt1[0] + cos360($v2_angle * 2) * 40 * meter_arc,
		$pt1[1] + sin360($v2_angle * 2) * 40 * meter_arc
	);
	@{ $segments[1]->path->seq->[1] }= @pt2;
	render_elbow(\@segments);
}

sub render_elbow {
	my $segments= shift;
	for (@$segments) {
		# View the line segment
		setcolor '#770077';
		plot_xyz(GL_LINE_STRIP, map vector_latlon(@$_)->xyz, @{ $_->path->seq });
	}
	my @polygons;
	my $search_result= {
		entities => { map +( $_ => $_ ), @segments },
	};
	my $to_render= $map3d->generate_route_polygons($search_result);
	for (@$to_render) {
		setcolor '#77FF77';
		plot_xyz(GL_LINE_LOOP, map $_->xyz, @$_)
			for @{ $_->{polygons} };
	}
	
	# 1. Calculate the unit-length "side" vectors for each segment.
	# 2. Find the projection of each vector along the other's unit-side.
	# 3. One will be positive, and one will be negative.  This tells which side the accute angle is on.
	# 4. Calculate each vector times width/projection to find the elbow point.
	# 5. If the magnitude of the elbow is longer than a vector, make the road a triangle to the pivot
	#    and reduce the width of the road to be the distiance to the other vector truncated to the same length.
	# 6. 
	#
	#
	#my $pivot= [ llxyz(@{ $segments->[0]->path->seq->[0] }) ];
	#my $p0= [ llxyz(@{ $segments->[0]->path->seq->[1] }) ];
	#my $width0= $map3d->calc_road_width($segments->[0]);
	#my $p1= [ llxyz(@{ $segments->[1]->path->seq->[1] }) ];
	#my $width1= $map3d->calc_road_width($segments->[1]);
	#my $p0_svec= [ $map3d->_calc_side_vec($pivot, $p0, $width0) ];
	#my $p1_svec= [ $map3d->_calc_side_vec($pivot, $p1, $width1) ];
	#my $p0_vec= [ vec_add($p0, [vec_neg($pivot)]) ];
	#my $p1_vec= [ vec_add($p1, [vec_neg($pivot)]) ];
	#my $p0_ssvec= [ vec_scale($p0_svec, $width0/2) ];
	#my $p1_ssvec= [ vec_scale($p1_svec, $width1/2) ];
	#my $p1v_proj_p0s= abs(vec_proj($p1_vec, $p0_svec));
	#my $p1ev= [ vec_add($pivot, [vec_scale($p1_vec, $width0*.5/$p1v_proj_p0s)]) ];
	#my $p0v_proj_p1s= abs(vec_proj($p0_vec, $p1_svec));
	#my $p0ev= [ vec_add($pivot, [vec_scale($p0_vec, $width1*.5/$p0v_proj_p1s)]) ];
	#my $p10ev= [ vec_add($p1ev, [vec_scale($p0_vec, $width1*.5/$p0v_proj_p1s)]) ];
	##printf "pivot ( %.8lf,%.8lf,%.8lf ) p0  ( %.8lf,%.8lf,%.8lf ) p1  ( %.8lf,%.8lf,%.8lf )\n"
	##	  ."  p0v ( %.8lf,%.8lf,%.8lf ) p1s ( %.8lf,%.8lf,%.8lf ) dot %.8lf wid %.8lf\n"
	##	  ." p0ev ( %.8lf,%.8lf,%.8lf )\n",
	##	  @$pivot, @$p0, @$p1, @$p1_vec, @$p0_svec, $p0v_proj_p1s, $width1, @$p1ev;
	#setcolor '#777700';
	#plot_xyz(GL_LINE_LOOP,
	#	vec_add($pivot,$p0_ssvec), vec_add($p0,$p0_ssvec), vec_add($p0,[vec_neg($p0_ssvec)]),
	#	vec_add($pivot,[vec_neg($p0_ssvec)])
	#);
	#setcolor '#007777';
	#plot_xyz(GL_LINE_LOOP,
	#	vec_add($pivot,$p1_ssvec), vec_add($p1,$p1_ssvec), vec_add($p1,[vec_neg($p1_ssvec)]),
	#	vec_add($pivot,[vec_neg($p1_ssvec)])
	#);
	#setcolor '#FFFF00';
	#plot_xyz(GL_LINES,
	#	@$pivot, @$p1ev,
	#	@$pivot, @$p0ev,
	#	@$pivot, @$p10ev,
	#	@$pivot, vec_neg($p10ev),
	#);
}

my $globe_list;
sub globe {
	$globe_list //= do {
		my $list= OpenGL::Sandbox::V1::DisplayList->new;
		$list->compile(sub {
			setcolor '#44FF44';
			for my $lon (1..90) {
				plot_xyz(GL_LINE_STRIP, map vector_latlon($_, $lon)->xyz, 0..360);
			}
			setcolor '#FF4444';
			for my $lon (91..180) {
				plot_xyz(GL_LINE_STRIP, map vector_latlon($_, $lon)->xyz, 0..360);
			}
			setcolor '#4444FF';
			for my $lat (-80..89) {
				plot_xyz(GL_LINE_STRIP, map vector_latlon($lat, $_)->xyz, 0..360);
			}
		});
		$list;
	};
	$globe_list->call;
}
