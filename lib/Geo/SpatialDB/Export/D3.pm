package Geo::SpatialDB::Export::D3;
use Moo 2;

use Carp;
use Try::Tiny;
use Log::Any '$log';
use Time::HiRes 'time';
use Math::Trig 'deg2rad','spherical_to_cartesian', 'pip2';

has spatial_db   => is => 'rw', required => 1;
has earth_radius => is => 'rw', required => 1, default => sub { 1 };

sub _latlon_to_xyz_coderef {
	my $self= shift;
	my $scale= deg2rad(1 / $self->spatial_db->latlon_scale);
	my $rad=   $self->earth_radius;
	return sub {
		[ spherical_to_cartesian( $rad, $_[0][1] * $scale, pip2 - $_[0][0] * $scale ) ]
	};
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

sub latlon_to_cartesian {
	my $self= shift;
	my $latlon_to_xyz= $self->_latlon_to_xyz_coderef;
	map { $latlon_to_xyz->($_) } @_;
}

sub generate_route_polygons {
	my ($self, $geo_search_result, %opts)= @_;
	my @quads;
	my $cb= $opts{callback} // sub { push @quads, [ @_ ] };
	my $road_width= $opts{road_width} // $self->earth_radius * 1/3000000;
	my $latlon_clip= $opts{latlon_clip};
	my $plane_clip= $latlon_clip && $self->_latlon_clip_to_plane_clip($latlon_clip);
	my $latlon_to_xyz= $self->_latlon_to_xyz_coderef;
	for my $ent (values %{ $geo_search_result->{entities} }) {
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

sub _latlon_clip_to_plane_clip {
	my ($self, $bbox)= @_;
	warn "Unimplemented";
	return [];
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

1;
