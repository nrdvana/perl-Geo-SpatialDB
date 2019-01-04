package Geo::SpatialDB::Export::MapPolygon3D;

use Moo 2;
use Carp;
use Try::Tiny;
use Log::Any '$log';
use Time::HiRes 'time';
use Math::Trig 'deg2rad','spherical_to_cartesian', 'pip2';
use Geo::SpatialDB::Export::MapPolygon3D::Vector 'vector';
use Geo::SpatialDB::Export::MapPolygon3D::Polygon 'polygon';

# ABSTRACT: Export map data as polygons in 3D

=head1 DESCRIPTION

This exports streets and other areas as collections of polygons plotted in 3D on the surface
of a sphere.

=head2 Coordinates

Latitude and Longitude are in B<Degrees> and the Earth is assumed to be a sphere with radius of
exactly 1.

The spherical-to-cartesian mapping comes from L<Math::Trig>, but also compensating for latitude
of zero to be at the equator rather than the north pole.  The North pole is (0,0,1), the South
pole is (0,0,-1), the equator is represented by Z=0, and the Prime Meridian is represented by
Y=0.  The polar (0,90) near India/Malaysia is cartesian (0,1,0), and the polar (0,-90) near the
Galapagos west of Brazil is cartesian (0,-1,0).  (0,0) near the Gulf of Guinea is (1,0,0), and
(0,180) on the international date line is (-1,0,0).

=head1 ATTRIBUTES

=head2 spatial_db

Reference to a Geo::SpatialDB from which the rendered entities came.

=head2 earth_radius

Earth radius, in Meters.  This helps when converting to/from the earth-radius unit vectors that
this module returns for all cartesian coordinates.

=head2 lane_width

The width of one lane of road, in meters.

=cut

has spatial_db   => is => 'rw', required => 1;
has earth_radius => is => 'rw', default => sub { 6371000 }; # meters
has lane_width   => is => 'rw', default => sub { 3 }; # meters

=head1 METHODS

=head2 latlon_to_cartesian

Convert a series of C<< [$lat,$lon] >> into a flat list of C<< ($x,$y,$z) >>.

=cut

# Returns a coderef which calculates
#   ($x, $y, $z)= $coderef->([$lat, $lon]);
sub _latlon_to_xyz_coderef {
	my $self= shift;
	my $scale= deg2rad(1 / $self->spatial_db->latlon_scale);
	return sub {
		spherical_to_cartesian( 1, $_[1] * $scale, pip2 - $_[0] * $scale )
	};
}

sub latlon_to_cartesian {
	my $self= shift;
	my $latlon_to_xyz= $self->_latlon_to_xyz_coderef;
	map { $latlon_to_xyz->($_) } @_;
}

sub calc_road_width {
	my ($self, $route_segment)= @_;
	$route_segment->lanes * $self->lane_width / $self->earth_radius;
}

sub generate_route_lines {
	my ($self, $geo_search_result, %opts)= @_;
	my @lines;
	my $cb= $opts{callback} // sub { push @lines, [ @_ ] };
	my $latlon_clip= $opts{latlon_clip};
	my $latlon_to_xyz= $self->_latlon_to_xyz_coderef;
	for my $ent (values %{ $geo_search_result->{entities} }) {
		if ($ent->isa('Geo::SpatialDB::RouteSegment')) {
			my $path= $ent->path
				or next;
			$cb->($ent, [ map { $latlon_to_xyz->($_) } @$_ ])
				for $latlon_clip? @{ $self->_latlon_clip($latlon_clip, $path) } : $path;
		}
	}
	\@lines;
}

=head2 generate_route_polygons

  my $data= $self->generate_route_polygons($geo_search_result, %opts);
  # {
  #   vbuf => pack('d*', ...),
  #   tbuf => pack('f*', ...),
  #   routes => [
  #     [ $route, $vertex_offset, $polygon_count ],
  #     ...
  #   ],
  #   normal => [ $i, $j, $k ]
  # }

Returns a packed buffer of double-precision triangle geometry (x,y,z) and a packed buffer of
single-precision texture coordinates (s,t) and an array that maps each route segment to an
array of polygons.  The polygon coordinates describe points on a unit sphere of the Earth,
thus the need for double precision.  Only one normal is generated, since for a standard tile
they would all be identical at single-precision.

=cut

sub generate_route_polygons {
	my ($self, $geo_search_result, %opts)= @_;
	my @plane_clip= $opts{latlon_clip}? $self->_bbox_to_planes($opts{latlon_clip}) : ();
	my %isec; # points-of-intersection
	my %path_polygons;
	# Need to know all intersections of route segments, in order to render the intersections correctly
	for my $ent (values %{ $geo_search_result->{entities} }) {
		# route segments must have more than one vertex for any of the rest of the code to work
		if ($ent->isa('Geo::SpatialDB::RouteSegment') && @{$ent->path->seq} > 1) {
			my ($start, $end)= @{$ent->endpoint_keys};
			$isec{$start}{$ent->path->id}= { seg => $ent, at => 0, peer => $end };
			$isec{$end}{$ent->path->id}=   { seg => $ent, at => -1, peer => $start };
		}
	}
	# Process all the routes, attempting to follow paths from intersections
	# with more than 3 roads first, passing through intersections with 2 paths
	# as if it was a single path.
	for my $isec (sort { scalar(keys %$b) <=> scalar(keys %$a) } values %isec) {
		# Process each segment that comes from this intersection
		for (keys %$isec) {
			next if exists $path_polygons{$_};
			my $cur_path_id= $_;
			my $cur_isec= $isec;
			while (1) {
				my $next_isec= $isec->{ $cur_isec->{$cur_path_id}{peer} };
				$path_polygons{$cur_path_id}= $self->_generate_route_segment_polygons(
					$isec->{$cur_path_id}{seg},
					$isec->{$cur_path_id}{at} == 0? ( $isec, $peer_isec ) : ( $peer_isec, $isec )
				);
				last if scalar(%$next_isec) != 2;
				($next_path_id)= grep $_ != $cur_path_id, keys %$next_isec;
				last unless $next_path_id && !$path_polygons{$next_path_id};
				$cur_isec= $next_isec;
				$cur_path_id= $next_path_id;
			}
		}
		# At this point, all paths out of this intersection have been processed.
		# If more than 2 paths, build a polygon from the accumulated geometry,
		# then clip the polygons at the ends of each path.
		next unless keys %$isec > 2;
		# Sort vectors by angle, counter-clockwise
		my @exits= values %$isec;
		my $center= $exits[0]{point};
		my $angle0= $exits[0]{side_unit_vector};
		my $angle90= $center->cross($angle0)->normalize;
		@exits= sort { $angle0->angle_cmp($angle90, $a->{side_unit_vector}, $b->{side_unit_vector}) } @exits;
		for (@exits) {
			...
			#my $p0_vec= [ vec_add($p0, [vec_neg($pivot)]) ];
			#my $p1_vec= [ vec_add($p1, [vec_neg($pivot)]) ];
			#my $p0_ssvec= [ vec_scale($p0_svec, $width0/2) ];
			#my $p1_ssvec= [ vec_scale($p1_svec, $width1/2) ];
			#my $p1v_proj_p0s= abs(vec_proj($p1_vec, $p0_svec));
			#my $p1ev= [ vec_add($pivot, [vec_scale($p1_vec, $width0*.5/$p1v_proj_p0s)]) ];
			#my $p0v_proj_p1s= abs(vec_proj($p0_vec, $p1_svec));
			#my $p0ev= [ vec_add($pivot, [vec_scale($p0_vec, $width1*.5/$p0v_proj_p1s)]) ];
			#my $p10ev= [ vec_add($p1ev, [vec_scale($p0_vec, $width1*.5/$p0v_proj_p1s)]) ];
		}
	}
	# Then clip polygons to the BBox
	$polygons= $self->_clip_triangles($polygons, \@plane_clip)
		if @plane_clip;
	return $polygons;
}

sub _generate_route_segment_polygons {
	my ($self, $segment, $start_isec, $end_isec)= @_;
	
	# TODO: for each intersection, calculate:
	#   point
	#   exit vector (toward next path point)
	#   side unit vector (toward road's right-hand)
	#   road width
	
	my $latlon_to_xyz= $self->_latlon_to_xyz_coderef;
	my @path= map vector($latlon_to_xyz->(@$_)), @{ $segment->path->seq };
	# Iterate from an intersection with known t_pos, if possible.
	if (defined $start_isec->{t_pos}) {
		# forward iteration from a previous processed segment
		$prev_side_unit= $start_isec->{
	}
	else {
	}
	my ($t_pos, $t_scale, $clip_plane, $clip_end, $prev_poly, $prev_side_unit)=
		@{$plot_state}{qw( t_pos t_scale clip_start clip_end prev_poly prev_side_unit )};
	my $width_2= $self->calc_road_width($segment) * .5;
	my @polygons;
	# If caller gives clip_plane, it is assumed the previous polygon was already clipped.
	# If caller gives prev_poly, it means we are continuing another segment and previous
	#   still needs extended and clipped.  Previous is assumed to be a quad with vertices
	#   [-2] and [-1] being un-clipped.
	$prev_side_unit= undef if $clip_plane;
	$path[0]->set_st(0.5, $t_pos || 0);
	$t_scale ||= 1/($self->lane_width/$self->earth_radius);
	for (1..$#path) {
		my ($p0, $p1)= @path[$_-1, $_];
		my $vec= $p1->clone->sub($p0);
		my $veclen= $vec->mag;
		# The texture 't' coordinate will progress at a rate of $t_scale to the length of the vector.
		$vec->set_st(0, $veclen * $t_scale);
		$p1->set_st(0.5, $p0->t + $vec->t);
		# Now calculate vector to right-hand side of road
		my $side_unit= $vec->cross($p0)->normalize;
		# Side vec is unit length.  Now calculate the offset of half the width of the road
		my $side= $side_unit->clone->scale($width_2)->set_st(.5,0);
		#printf STDERR "# p0=(%.8f,%.8f,%.8f, %.4f,%.4f) p1=(%.8f,%.8f,%.8f, %.4f,%.4f)\n", @$p0, @$p1;
		#printf STDERR "# vec=(%.8f,%.8f,%.8f, %.4f,%.4f)\n", @$vec;
		#printf STDERR "# side=(%.8f,%.8f,%.8f, %.4f,%.4f)\n", @$side;
		# If there is a previous clipping plane, clip against that.
		# Else if there is a previous side vector, compute the clipping plane from that.
		if ($prev_side_unit) {
			# The clipping plane follows the sum of the two side vectors, so the plane vector
			# is the cross product of their sum.
			$clip_plane= $side_unit->clone->add($prev_side_unit)->cross($p0)
				->set_projection_origin($p0);
			# Also clip the previous polygon
			($polygons[-1] || $prev_poly)->clip_to_planes($clip_plane);
			$clip_plane->scale(-1); # invert, for clipping current polygon
		}
		
		# If there is a starting or ending clip plane, elongate the polygon by $width/2 on that end
		# so that clipping it will reach to the other polygon on the far corner.
		# If the angle is too acute, there will be a gap, but it would be too much effort to round
		# those corners here.
		my $vec_overhang;
		#if ($clip_plane || !defined $clip_plane) {
			$vec_overhang //= $vec->clone->normalize->scale($width_2);
			$p0= $p0->clone->sub($vec_overhang);
		#}
		#if ($_ < $#path || $clip_end || !defined $clip_end) {
			$vec_overhang //= $vec->clone->normalize->scale($width_2);
			$p1= $p1->clone->add($vec_overhang);
		#}
		#printf STDERR "# vec_overhang=(%.8f,%.8f,%.8f, %.4f,%.4f)\n", @{$vec_overhang||[0,0,0,0,0]};
		#printf STDERR "# p0=(%.8f,%.8f,%.8f, %.4f,%.4f) p1=(%.8f,%.8f,%.8f, %.4f,%.4f)\n", @$p0, @$p1;
		my $rect= polygon(
			$p0->clone->sub($side), $p0->clone->add($side),
			$p1->clone->add($side), $p1->clone->sub($side),
		);
		#printf STDERR "# v0=(%.8f,%.8f,%.8f, %.4f,%.4f) v1=(%.8f,%.8f,%.8f, %.4f,%.4f)\n", @{$rect->[0]}, @{$rect->[1]};
		$rect->clip_to_planes($clip_plane) if $clip_plane;
		push @polygons, $rect;
		$prev_side_unit= $side_unit;
	}
	if (@polygons) {
		# Finally, clip by $clip_end if caller gave us one
		$polygons[-1]->clip_to_planes($clip_end) if $clip_end;
		$plot_state->{t_pos}= $path[-1]->t;
		$plot_state->{prev_poly}= $polygons[-1];
		$plot_state->{prev_side_unit}= $prev_side_unit;
	}
	return \@polygons;
}

sub _latlon_clip {
	my ($self, $bbox, $path)= @_;
	my @clipped;
	# This just checks whether two adjacent points are outside the same plane,
	# and if so, skips the segment.
	# It doesn't correctly exclude the segment in the case where a line crosses two
	# planes at once outside the corner of the box and isn't visible.
	# We don't actually clip the line segments at the intersection because
	# they aren't really "lines" yet until we convert to cartesian coordinates.
	my ($lat0, $lon0, $lat1, $lon1)= @$bbox;
	my $tmp;
	for (@$path) {
		if ($tmp and
			(  ($_->[0] < $lat0 and $tmp->[-1][0] < $lat0)
			or ($_->[0] > $lat1 and $tmp->[-1][0] > $lat1)
			or ($_->[1] < $lon0 and $tmp->[-1][1] < $lon0)
			or ($_->[1] > $lon1 and $tmp->[-1][1] > $lon1)
			)
		) {
			push @clipped, $tmp
				if @$tmp > 1;
			$tmp= undef;
		}
		push @$tmp, $_;
	}
	push @clipped, $tmp
		if $tmp and @$tmp > 1;
	\@clipped;
}

sub _bbox_to_clip_planes {
	my ($self, $bbox)= @_;
	my ($lat0, $lon0, $lat1, $lon1)= @$bbox;
	my $to_xyz= $self->_latlon_to_xyz_coderef;
	# CCW around region
	my @corners= (
		vector($to_xyz->($lat0,$lon0)), vector($to_xyz->($lat0,$lon1)),
		vector($to_xyz->($lat1,$lon1)), vector($to_xyz->($lat1,$lon0))
	);
	# Planes always have D=0 (of AX+BY+CZ=D) since they pass through the origin.
	return (
		$corners[3]->cross($corners[0]), # west
		$corners[1]->cross($corners[2]), # east
		$corners[0]->cross($corners[1]), # south
		$corners[2]->cross($corners[3]), # north
	);
}

sub _clip_line_segments {
	my ($self, $segments, $planes)= @_;
	my @result;
	for (@$segments) {
		my ($x0,$y0,$z0, $x1,$y1,$z1)= @$_;
		#printf STDERR "# (%9.5f,%9.5f,%9.5f) -> (%9.5f,%9.5f,%9.5f)\n", ($x0,$y0,$z0, $x1,$y1,$z1);
		my ($in, $clipped)= (1, 0);
		for (@$planes) {
			my $d0= $x0*$_->[0] + $y0*$_->[1] + $z0*$_->[2];
			my $d1= $x1*$_->[0] + $y1*$_->[1] + $z1*$_->[2];
			#printf STDERR "# plane = %9.5f x + %9.5f y + %9.5f z;  d0 = %9.5f  d1 = %9.5f\n", @$_, $d0, $d1;
			if (($d0 < 0) ne ($d1 < 0)) {
				my $pos= $d0 / ($d0 - $d1);
				($d0 < 0? ($x0, $y0, $z0) : ($x1, $y1, $z1))=
					($x0+($x1-$x0)*$pos, $y0+($y1-$y0)*$pos, $z0+($z1-$z0)*$pos);
				$clipped= 1;
				#printf STDERR "# clipped at pos= %9.5f\n", $pos;
				#printf STDERR "# (%9.5f,%9.5f,%9.5f) -> (%9.5f,%9.5f,%9.5f)\n", ($x0,$y0,$z0, $x1,$y1,$z1);
			}
			elsif ($d0 < 0) {
				# Line begins and ends on wrong side of plane
				$in= 0;
				#printf STDERR "# eliminated\n";
				last;
			}
		}
		push @result, ($clipped? [$x0,$y0,$z0, $x1,$y1,$z1] : $_)
			if $in;
	}
	return \@result;
}

1;
