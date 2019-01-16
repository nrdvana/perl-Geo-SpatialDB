#! /usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use OpenGL::Sandbox qw( -V1 :all glLoadIdentity glEnable glDisable glBlendFunc glShadeModel glClearColor
	GL_LINES GL_LINE_STRIP GL_LINE_LOOP GL_POLYGON GL_SMOOTH GL_SRC_ALPHA GL_ONE GL_TEXTURE_2D GL_BLEND GL_COLOR_MATERIAL GL_CLAMP );

$res->resource_root_dir("$FindBin::Bin/../share");
$res->tex_config({
	'intersection-2lane' => { wrap_s => GL_CLAMP, wrap_t => GL_CLAMP },
});

use Math::Trig qw( deg2rad );
use Geo::SpatialDB;
use Geo::SpatialDB::Entity::RouteSegment;
sub RouteSegment { Geo::SpatialDB::Entity::RouteSegment->new(@_) }
use Geo::SpatialDB::Path;
use Geo::SpatialDB::Export::MapPolygon3D;
use Geo::SpatialDB::Math 'vector_latlon';
my $sdb= Geo::SpatialDB->new(storage => { CLASS => 'Memory' }, latlon_scale => 1);
my $map3d= Geo::SpatialDB::Export::MapPolygon3D->new(spatial_db => $sdb);

sub sin360 { sin(deg2rad(shift)) }
sub cos360 { cos(deg2rad(shift)) }
sub meter_arc() { 360 / 40075000; } # a meter of earth's surface, in degrees

my $v2_angle= 0;
my $v3_angle= 0;
my @segments= (
	RouteSegment->new(
		id => 1,
		latlon_seq => [ (meter_arc*100,0), (0,0) ],
		lanes => 2,
	),
	RouteSegment->new(
		id => 2,
		latlon_seq => [ (0,0), (0,0), (0,0) ],
		lanes => 2,
	),
	RouteSegment->new(
		id => 3,
		latlon_seq => [ (0,0), (0,0) ],
		lanes => 2,
	),
);

make_context;
setup_projection( top => .000005, bottom => -.000005, ortho => 1, near => -1, far => 1, z => 0);
glEnable(GL_TEXTURE_2D);
glClearColor(.1,.1,.1,1);
while (1) {
	next_frame;
	#trans 0,0,-1.5;
	rotate x => -90;
	rotate z => 90;
	#scale 1, 1, 1;
	globe();
	$v2_angle -= 20/60; # degrees per 1/60 second
	$v3_angle -= 10/60;
	my @pt1= (  # 20 meter road, rotated around the intersection
		cos360($v2_angle) * 20 * meter_arc,
		sin360($v2_angle) * 20 * meter_arc
	);
	$segments[1]->latlon_seq->@[2,3]= @pt1;
	my @pt2= (
		$pt1[0] + cos360($v2_angle * 2) * 40 * meter_arc,
		$pt1[1] + sin360($v2_angle * 2) * 40 * meter_arc
	);
	$segments[1]->latlon_seq->@[4,5]= @pt2;
	my @pt3= ( # 30 meter rd, rotated around the intersection at half the speed
		cos360($v3_angle) * 30 * meter_arc,
		sin360($v3_angle) * 30 * meter_arc
	);
	$segments[2]->latlon_seq->@[2,3]= @pt3;
	render_elbow(\@segments);
}

sub render_elbow {
	my $segments= shift;
	glDisable(GL_TEXTURE_2D);
	for (@$segments) {
		# View the line segment
		setcolor '#770077';
		plot_xyz(GL_LINE_STRIP, map $_->xyz, $_->latlon_seq_pts->@*);
	}
	glEnable(GL_TEXTURE_2D);
	my @polygons;
	my $search_result= {
		entities => { map +( $_ => $_ ), @segments },
	};
	my $to_render= $map3d->generate_route_polygons($search_result);
	setcolor '#FFFFFF';
	for (@$to_render) {
		if ($_->{entity}) {
			$res->tex('road-2lane')->bind;
			plot_st_xyz(GL_POLYGON, map +($_->st, $_->xyz), @$_) for $_->{polygons}->@*;
		} else {
			$res->tex('intersection-2lane')->bind;
			#glDisable(GL_TEXTURE_2D);
			#setcolor '#22FF00';
			plot_st_xyz(GL_POLYGON, map +($_->st, $_->xyz), @$_) for $_->{polygons}->@*;
			#glEnable(GL_TEXTURE_2D);
			#for @{ $_->{polygons} };
		}
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
