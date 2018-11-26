package Geo::SpatialDB::Export::MapPolygon3D;

use Moo 2;
use Carp;
use Try::Tiny;
use Log::Any '$log';
use Time::HiRes 'time';
use Math::Trig 'deg2rad','spherical_to_cartesian', 'pip2';

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

=cut

has spatial_db   => is => 'rw', required => 1;

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
	my @quads;
	my $cb= $opts{callback} // sub { push @quads, [ @_ ] };
	my $road_width= $opts{road_width} // $self->earth_radius * 1/3000000;
	my $latlon_clip= $opts{latlon_clip};
	my $plane_clip= $latlon_clip && $self->_latlon_clip_to_plane_clip($latlon_clip);
	my $latlon_to_xyz= $self->_latlon_to_xyz_coderef;
	for my $ent (grep values %{ $geo_search_result->{entities} }) {
		if ($ent->isa('Geo::SpatialDB::RouteSegment')) {
			my $path= $ent->path
				or next;
			# TODO: option to determine road width per road type
			$cb->($ent, $self->_cartesian_path_to_polygons($road_width, $plane_clip,
					[ map { $latlon_to_xyz->($_) } @$_ ]
				))
				for $latlon_clip? @{ $self->_latlon_clip($latlon_clip, $path) } : $path;
		}
	}
	\@quads;
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

sub _bbox_to_planes {
	my ($self, $bbox)= @_;
	my ($lat0, $lon0, $lat1, $lon1)= @$bbox;
	return (
		[ $self->_geo_plane_normal($lat1,$lon0,$lat0,$lon0) ], # west
		[ $self->_geo_plane_normal($lat0,$lon1,$lat1,$lon1) ], # east
		[ $self->_geo_plane_normal($lat0,$lon0,$lat0,$lon1) ], # south
		[ $self->_geo_plane_normal($lat1,$lon1,$lat1,$lon0) ], # north
	);
}

sub _clip_line_segments {
	my ($self, $segments, $planes)= @_;
	my @result;
	for (@$segments) {
		my ($x0,$y0,$z0, $x1,$y1,$z1)= @$_;
		printf STDERR "# (%9.5f,%9.5f,%9.5f) -> (%9.5f,%9.5f,%9.5f)\n", ($x0,$y0,$z0, $x1,$y1,$z1);
		my ($in, $clipped)= (1, 0);
		for (@$planes) {
			my $d0= $x0*$_->[0] + $y0*$_->[1] + $z0*$_->[2];
			my $d1= $x1*$_->[0] + $y1*$_->[1] + $z1*$_->[2];
			printf STDERR "# plane = %9.5f x + %9.5f y + %9.5f z;  d0 = %9.5f  d1 = %9.5f\n", @$_, $d0, $d1;
			if (($d0 < 0) ne ($d1 < 0)) {
				my $pos= $d0 / ($d0 - $d1);
				($d0 < 0? ($x0, $y0, $z0) : ($x1, $y1, $z1))=
					($x0+($x1-$x0)*$pos, $y0+($y1-$y0)*$pos, $z0+($z1-$z0)*$pos);
				$clipped= 1;
				printf STDERR "# clipped at pos= %9.5f\n", $pos;
				printf STDERR "# (%9.5f,%9.5f,%9.5f) -> (%9.5f,%9.5f,%9.5f)\n", ($x0,$y0,$z0, $x1,$y1,$z1);
			}
			elsif ($d0 < 0) {
				# Line begins and ends on wrong side of plane
				$in= 0;
				printf STDERR "# eliminated\n";
				last;
			}
		}
		push @result, ($clipped? [$x0,$y0,$z0, $x1,$y1,$z1] : $_)
			if $in;
	}
	return \@result;
}

sub _cartesian_path_to_polygons {
	my ($self, $width, $plane_clip, $path)= @_;
	my @points;
	my ($prev_x, $prev_y, $prev_z);
	# cur vec, prev vec, sideways vec, prev sideways vec
	my ($cx, $cy, $cz, $px, $py, $pz, $sx, $sy, $sz, $psx, $psy, $psz);
	for (@$path) {
		($cx, $cy, $cz)= @$_;
		if (defined $pz) {
			# Cross product of the two points (each a unit vector from the earth's core)
			# Cur X Prev result in a vector to the "right hand" of the direction of the road.
			# Magnitude is 1, so result is unit, and scale to desired width of road.
			$sx= ( $cy*$pz - $cz*$py );
			$sy= ( $cz*$px - $cx*$pz );
			$sz= ( $cx*$py - $cy*$px );
			next unless $sx || $sy || $sz;
			my $scale= $width / sqrt($sx*$sx + $sy*$sy + $sz*$sz);
			$sx*=$scale; $sy*=$scale; $sz*=$scale;
			# Counter-clockwise order, left side of road then right side
			if (defined $psz) {
				($psx, $psy, $psz, $sx, $sy, $sz)= (
					$sx, $sy, $sz,
					($sx+$psx)*.5, ($sy+$psy)*.5, ($sz+$psz)*.5
				);
				# TODO: stretch sx,sy,sz if the corner is more than 45 degrees
			} else {
				($psx, $psy, $psz)= ($sx, $sy, $sz);
			}
			
			# TODO: optionally include texture coordinates
			push @points,
				[ $px - $sx, $py - $sy, $pz - $sz ],
				[ $px + $sx, $py + $sy, $pz + $sz ];
		}
		($px, $py, $pz)= ($cx, $cy, $cz);
	}
	if (defined $sx) {
		push @points,
			[ $cx - $sx, $cy - $sy, $cz - $sz ],
			[ $cx + $sx, $cy + $sy, $cz + $sz ];
	}
	# TODO: is it possible to clip vs planes and still have a simple strip of triangles?
	\@points;
}

# Calculate the plane passing through two (lat,lon) points and the origin.
# returns (A, B, C) of Ax+By+Cz=D where D is always 0.
sub _geo_plane_normal {
	my ($self, $lat0, $lon0, $lat1, $lon1)= @_;
	my $to_xyz= $self->_latlon_to_xyz_coderef;
	my ($x0, $y0, $z0)= $to_xyz->($lat0, $lon0);
	my ($x1, $y1, $z1)= $to_xyz->($lat1, $lon1);
	my ($x, $y, $z)= (
		$y0*$z1 - $z0*$y1,
		$z0*$x1 - $x0*$z1,
		$x0*$y1 - $y0*$x1,
	);
	my $mag_sq= $x*$x+$y*$y+$z*$z
		or return (0,0,0);
	my $scale= 1.0/sqrt($mag_sq);
	#_assert_unit_length($x*$scale, $y*$scale, $z*$scale);
	return ($x*$scale, $y*$scale, $z*$scale);
}
sub _assert_unit_length {
	my $mag_sq= $_[0]*$_[0]+$_[1]*$_[1]+$_[2]*$_[2]; 
	$mag_sq > 0.9999999999 && $mag_sq < 1.0000000001 or die "BUG: not unit length: $mag_sq";
}

1;
