package Geo::SpatialDB::Export::MapPolygon3D;

use Moo 2;
use Carp;
use Try::Tiny;
use Log::Any '$log';
use Time::HiRes 'time';
use Geo::SpatialDB::Math qw( vector vector_latlon polygon );

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

=head2 calc_road_width

  my $width= $export->calc_road_width($route_segment);

Use details about the route segment to determine it's real-world width.  However, the width is
returned in units of earth-radius, consistent with the unit-length polar coordinates returned
for the road vertices.

=cut

sub calc_road_width {
	my ($self, $route_segment)= @_;
	$route_segment->lanes * $self->lane_width / $self->earth_radius;
}

=head2 generate_route_lines

  my $list= $self->generate_route_lines($geo_search_result, %options);
  # [
  #   { entity => $entity, line_strip => [ $vertex, $vertex, ... ] },
  #   ...
  # ]

Return an arrayref of entries which describe sequences of line strips.  The entity is used to
determine how the line should be drawn.  The line_strip is a sequence of 3D points (Vector
objects, actually) which can be accessed as simple arrays of C<< [$x,$y,$z] >>.

If the line is broken by a clipping plane, it results in two entries for the same entity,
each with an un-broken line_strip.

=cut

sub generate_route_lines {
	my ($self, $geo_search_result, %opts)= @_;
	my @entries;
	my $latlon_clip= $opts{latlon_clip};
	for my $ent (values %{ $geo_search_result->{entities} }) {
		if ($ent->isa('Geo::SpatialDB::RouteSegment')) {
			my $path= $ent->path
				or next;
			push @entries, { entity => $ent, line_strip => [ map vector_latlon(@$_), @$_ ] }
				for $latlon_clip? @{ $self->_latlon_clip($latlon_clip, $path) } : $path;
		}
	}
	\@entries;
}

=head2 generate_route_polygons

  my $data= $self->generate_route_polygons($geo_search_result, %options);
  # [
  #   { entity => $entity, polygons => [ $polygon, $polygon, ... ] },
  #   ...
  # ]

Returns an arrayref of entries which describe sets of polygons.  All polygons of each item use
the same texture, determined by the type of entity.  The polygons are individual convex polygons
and not necessarily joined in any way, or composed of any specific number of vertices.

=cut

sub generate_route_polygons {
	my ($self, $geo_search_result, %opts)= @_;
	my @plane_clip= $opts{latlon_clip}? $self->_bbox_to_planes($opts{latlon_clip}) : ();
	my %intersections; # points-of-intersection, keyed by "endpoint_keys", and values are path IDs that meet there.
	my %path_polygons;
	# %isec= (
	#   $endpoint_id => {
	#     $path_id => {
	#       seg   => $RouteSegment,
	#       at    => $path_idx,
	#       peer  => $other_endpoint_id,
	#       t_pos => $texture_t_coordinate,
	#       point => $cartesian_endpoint_vector,   # these are filled in by _generate_route_segment_polygons
	#       vec   => $cartesian_vector_from_point, #
	#       side  => $unit_sideways_vector,        #
	#       width => $road_width,                  #
	#       poly  => $polygon,                     #
	#     }
	#   }
	# )
	my @result;
	# Need to know all intersections of route segments, in order to render the intersections correctly
	for my $ent (values %{ $geo_search_result->{entities} }) {
		# route segments must have more than one vertex for any of the rest of the code to work
		if ($ent->isa('Geo::SpatialDB::RouteSegment') && @{$ent->path->seq} > 1) {
			my ($start, $end)= @{$ent->endpoint_keys};
			$intersections{$start}{$ent->path->id}= { seg => $ent, at =>  0, peer => $end, width => $self->calc_road_width($ent) };
			$intersections{$end  }{$ent->path->id}= { seg => $ent, at => -1, peer => $start, width => $self->calc_road_width($ent) };
		}
	}
	# Process all the routes, attempting to follow paths from intersections
	# with more than 3 roads first, passing through intersections with 2 paths
	# as if it was a single path.
	for my $isec_id (sort {
			((keys %{$intersections{$a}}) > 2? 0 : 1) <=> ((keys %{$intersections{$b}}) > 2? 0 : 1)
			or $a cmp $b
		} keys %intersections
	) {
		my $isec= $intersections{$isec_id};
		# Process each segment that comes from this intersection
		# Process whole road segment chains, starting from the intersection with the lowest ID.
		# In most cases, this will happen naturally from the sort order of the top loop,
		# but in cases of non-intersections of just 2 segments, we need to backtrack to each
		# end of the chain and iterate from whichever is lower.
		if (keys %$isec == 2) {
			my ($pathid0, $pathid1)= keys %$isec;
			my ($isecid0, $isecid1)= ($isec->{$pathid0}{peer}, $isec->{$pathid1}{peer});
			while (keys %{$intersections{$isecid0}} == 2) {
				my ($prev_path_id)= grep { $_ != $pathid0 } keys %{$intersections{$isecid0}};
				last if $path_polygons{$prev_path_id};
				$isecid0= $intersections{$isecid0}{$prev_path_id}{peer};
				$pathid0= $prev_path_id;
			}
			while (keys %{$intersections{$isecid1}} == 2) {
				my ($next_path_id)= grep { $_ != $pathid1 } keys %{$intersections{$isecid1}};
				last if $path_polygons{$next_path_id};
				$isecid1= $intersections{$isecid1}{$next_path_id}{peer};
				$pathid1= $next_path_id;
			}
			# then iterate from whichever has highest ID
			$isec= $intersections{$isecid0 le $isecid1? $isecid0 : $isecid1};
		}
		for (keys %$isec) {
			my $cur_isec= $isec;
			my $cur_path_id= $_;
			# Iterate forward along path so long as it hasn't been rendered and continues
			# through intersections of 2 segments.
			while (!exists $path_polygons{$cur_path_id}) {
				my $next_isec= $intersections{ $cur_isec->{$cur_path_id}{peer} };
				
				# collect the intersection-info for the start and end of the segment and
				# its adjacent segments.  Adjacent segments are only used if the intersection
				# has exactly two segments joined to it (i.e. a continuous path)
				my $start_info= $cur_isec->{$cur_path_id};
				my $end_info= $next_isec->{$cur_path_id};
				my $prev_info= (scalar keys %$cur_isec != 2)? undef
					: $cur_isec->{(grep { $_ != $cur_path_id } keys %$cur_isec)[0]};
				my $next_info= (scalar keys %$next_isec != 2)? undef
					: $next_isec->{(grep { $_ != $cur_path_id } keys %$next_isec)[0]};
				# Generate cartesian coordinates from each lat,lon pair
				my $seg= $cur_isec->{$cur_path_id}{seg};
				my @path= map vector_latlon(@$_), @{ $seg->path->seq };
				# If the next_info defines a t_pos (texture position) but the prev_info does not,
				# reverse the direction we iterate.  But also, need to reverse the path according
				# to the $start_info->{at} parameter.
				my $polygons= ($next_info && defined $next_info->{t_pos} && !($prev_info && defined $prev_info->{t_pos}))
					? $self->_generate_polygons_for_path(($start_info->{at}==0? [ reverse @path ] : \@path), $next_info, $end_info, $start_info, $prev_info)
					: $self->_generate_polygons_for_path(($start_info->{at}==0? \@path : [ reverse @path ]), $prev_info, $start_info, $end_info, $next_info);
				$path_polygons{$cur_path_id}= $polygons;
				push @result, { entity => $seg, polygons => $polygons };
				
				# If this segment ends in an "intersection" of two roads, continue rendering
				# the next segment as well so that the textures line up.
				last if scalar(keys %$next_isec) != 2;
				($cur_path_id)= grep $_ != $cur_path_id, keys %$next_isec;
				$cur_isec= $next_isec;
			}
		}
		# At this point, all paths out of this intersection have been processed.
		# If more than 2 paths, build a polygon from the accumulated geometry,
		# then clip the polygons at the ends of each path.
		next unless keys %$isec > 2;
		my $center= (values %$isec)[0]{point};  # all exits should have same point
		# Sort vectors by angle, counter-clockwise
		my %exits_by_vec= map { 0+$_->{side} => $_ } values %$isec;
		my @exits= map $exits_by_vec{0+$_}, $center->sort_vectors_by_heading(map $_->{side}, values %$isec);
		my @isec_corners;
		for (0 .. $#exits) {
			my ($e0, $e1)= @exits[$_-1, $_];
			# Find the point at which $exit->{vec}*$pct + $exit->{side} + $prev_exit->{side} falls onto the
			# plane along $prev_exit->{vec}.  Then, $exit->{vec}*$pct + $exit->{side} is the vertex.
			my $e1v_proj_e0s= abs($e0->{side}->project($e1->{vec}));
			my $e0v_proj_e1s= abs($e1->{side}->project($e0->{vec}));
			my $p0ev= $e0->{vec}->clone->scale($e0->{width}*.5/$e0v_proj_e1s)->add($center);
			my $p10ev= $e1->{vec}->clone->scale($e1->{width}*.5/$e1v_proj_e0s)->add($p0ev);
			push @isec_corners, $p10ev;
		}
		# For each line segment around the perimiter of the intersection, clip the adjacent road polygon
		for (0 .. $#exits) {
			my $edge_plane= $isec_corners[$_]->cross($isec_corners[$_-1])->normalize;
			$exits[$_-1]{poly}->clip_to_planes($edge_plane);
		}
		# Then add the intersection polygon
		push @result, { entity => undef, polygons => [ polygon(@isec_corners) ] };
	}
	return \@result;
}

sub _generate_polygons_for_path {
	my ($self, $path, $prev_info, $start_info, $end_info, $next_info)= @_;
	my $width=   $start_info->{width}   // croak "start_info->{width} is required";
	my $t_pos=   $start_info->{t_pos}   //= ($prev_info && $prev_info->{t_pos} || 0);
	my $t_scale= $start_info->{t_scale} //= 1/$width;
	# copy start_info constants to end_info
	$end_info->{$_} //= $start_info->{$_} for qw( width t_pos t_scale );
	
	my ($side, $vec, $wvec, $clip_plane, @polygons);
	my $prev_side= $prev_info && $prev_info->{side}? $prev_info->{side}->clone->scale(-1) : undef;
	my $prev_poly= $prev_info? $prev_info->{poly} : undef;
	$path->[0]->set_st(0.5, $t_pos || 0);
	for (1..$#$path) {
		# First, calculate everything about this segment of the path
		my ($p0, $p1)= @{$path}[$_-1 .. $_];
		$vec= $p1->clone->sub($p0);
		my $veclen= $vec->mag;
		# The texture 't' coordinate will progress at a rate of $t_scale to the length of the vector.
		$vec->set_st(0, $veclen * $t_scale);
		$p1->set_st(0.5, $p0->t + $vec->t);
		# Now calculate vector to right-hand side of road
		$side= $vec->cross($p0)->normalize;
		# Side vec is unit length.  Now calculate the offset of half the width of the road
		$wvec= $side->clone->scale($width * .5)->set_st(.5,0);
		
		# If there is a known previous segment, calculate the clipping plane and clip it.
		if ($prev_side) {
			# The clipping plane follows the sum of the two side vectors, so the plane vector
			# is the cross product of their sum.
			$clip_plane= $side->clone->add($prev_side)->cross($p0)
				->set_projection_origin($p0);
			# Also clip the previous polygon
			$prev_poly->clip_to_planes($clip_plane) if $prev_poly;
			$clip_plane->scale(-1); # invert, for clipping current polygon
		}
		
		# If there is a starting or ending clip plane, elongate the polygon on that end
		# so that clipping it will reach to the other polygon on the far corner.
		# If the angle is too acute, there will be a gap, but it would be too much effort to
		# round those corners here.  Better to adjust the input path to add more vertices.
		my $vec_overhang= $vec->clone->normalize->scale($width);
		$p0= $p0->clone->sub($vec_overhang) if $_ > 1 || $prev_info;
		$p1= $p1->clone->add($vec_overhang) if $_ < $#$path || $next_info;
		my $poly= polygon(
			$p0->clone->sub($wvec), $p0->clone->add($wvec),
			$p1->clone->add($wvec), $p1->clone->sub($wvec),
		);
		$poly->clip_to_planes($clip_plane) if $clip_plane;
		push @polygons, $poly;
		
		# If this was the first polygon, save the rendering info
		if ($_ == 1) {
			$start_info->{point} //= $path->[0];
			$start_info->{vec}   //= $vec;
			$start_info->{side}  //= $side;
			$start_info->{poly}  //= $poly;
		}
		($prev_side, $prev_poly)= ($side, $poly);
	}
	# Save the rendering info about the last segment
	if (@polygons) {
		$end_info->{point} //= $path->[-1];
		$end_info->{poly}  //= $polygons[-1];
		# vec and side vec need inverted to be exiting intersection rather than entering.
		$end_info->{vec}   //= $vec->clone->scale(-1);
		$end_info->{side}  //= $side->clone->scale(-1);
		
		# Then, if the next segment has been calculated, calculate the clip plane and
		# clip both that one and the end of this one.
		if ($next_info && $next_info->{side}) {
			$clip_plane= $side->clone->add($next_info->{side})->cross($path->[-1])
				->set_projection_origin($path->[-1]);
			$polygons[-1]->clip_to_plane($clip_plane);
			$next_info->{poly}->clip_to_plane($clip_plane->scale(-1))
				if $next_info->{poly};
		}
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
	# CCW around region
	my @corners= (
		vector_latlon($lat0,$lon0), vector_latlon($lat0,$lon1),
		vector_latlon($lat1,$lon1), vector_latlon($lat1,$lon0)
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
