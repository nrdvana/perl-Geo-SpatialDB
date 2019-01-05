package Geo::SpatialDB::Export::MapPolygon3D::Vector;
use strict;
use warnings;
use Carp 'croak';
use Exporter 'import';
use Math::Trig qw( spherical_to_cartesian deg2rad );
our @EXPORT_OK= qw( vector vector_latlon );

sub vector { __PACKAGE__->new(@_); }
sub vector_latlon { __PACKAGE__->new_latlon(@_); }

sub new {
	my ($class, @vec)= @_;
	@vec >= 2 or croak "Require at least x,y arguments to Vector->new";
	$vec[2] ||= 0;
	bless \@vec, ref($class)||$class;
}
sub new_latlon {
	$_[0]->new(spherical_to_cartesian( 1, deg2rad($_[2]), deg2rad(90-$_[1]) ));
}

sub clone {
	bless [ @{$_[0]} ], ref $_[0];
}

sub x : lvalue { $_[0][0] }
sub y : lvalue { $_[0][1] }
sub z : lvalue { $_[0][2] }
sub xyz    { @{$_[0]}[0..2] }
sub s : lvalue { $_[0][3] }
sub t : lvalue { $_[0][4] }
sub st     { @{$_[0]}[3..4] }
sub xyzst  { @{$_[0]}[0..4] }

sub set_xyz   { @{$_[0]}[0..2]= @_[1..$#_]; $_[0] }
sub set_st    { @{$_[0]}[3..4]= @_[1..$#_]; $_[0] }
sub set_xyzst { @{$_[0]}[0..4]= @_[1..$#_]; $_[0] }

# Abuse the vector class to include a projection offset
sub projection_offset : lvalue { $_[0][5] }

sub scale {
	$_ *= $_[1] for @{ $_[0] };
	$_[0]
}

sub add {
	$_[0][$_] += ($_[1][$_] || 0) for 0..$#{$_[0]};
	$_[0]
}
sub sub {
	$_[0][$_] -= ($_[1][$_] || 0) for 0..$#{$_[0]};
	$_[0]
}

sub dot {
	$_[0][0] * $_[1][0] + $_[0][1] * $_[1][1] + $_[0][2] * $_[1][2];
}

sub mag_sq {
	$_[0][0] * $_[0][0] + $_[0][1] * $_[0][1] * $_[0][2] * $_[0][2];
}

sub mag {
	sqrt($_[0][0] * $_[0][0] + $_[0][1] * $_[0][1] + $_[0][2] * $_[0][2])
}

sub normalize {
	my $mag_sq= $_[0][0] * $_[0][0] + $_[0][1] * $_[0][1] + $_[0][2] * $_[0][2];
	if ($mag_sq && $mag_sq != 1) {
		my $scale= 1/sqrt($mag_sq);
		$_[0][0] *= $scale;
		$_[0][1] *= $scale;
		$_[0][2] *= $scale;
	}
	$_[0]
}

sub cross {
	bless [
		$_[0][1]*$_[1][2] - $_[0][2]*$_[1][1],
		$_[0][2]*$_[1][0] - $_[0][0]*$_[1][2],
		$_[0][0]*$_[1][1] - $_[0][1]*$_[1][0],
	], ref $_[0];
}

=head2 sort_cclockwise

Sort a list of vectors in order of counter-clockwise "heading" relative to this vector as a
"pole".  The vectors do not need to be unit length or even perpendicular to this vector.
But, any vectors co-linear with this vector are discarded.

The first vector given (which is not co-linear with this vector) will be considered the
0-degree heading, and so also will be returned first.

=cut

sub sort_vectors_by_heading {
	my $self= shift;
	# Cross this vector with the first vector not co-linear with this one,
	# to create a "90 degree" vector.  Co-linear vectors are returned first.
	my @to_sort;
	my @to_sort_cross;
	for (@_) {
		my $vec90= $self->cross($_)->normalize;
		if ($vec90->[0] || $vec90->[1] || $vec90->[2]) {
			push @to_sort, $_;
			push @to_sort_cross, $vec90;
		}
	}
	# If there are two or fewer vectors, then they are automatically "sorted".
	return @to_sort unless @to_sort > 2;
	# consider first vector to be 0-degrees, and thus first cross is 90 degrees.
	# $self X vec90 gives a 180 vec, or 90 degree vec with respect to the other cross products.
	my $first= shift @to_sort;
	my $vec0= shift @to_sort_cross;
	my $vec90= $self->cross($vec0)->normalize;
	# vec0 and vec90 and all to_sort_cross are normal vectors now, so no more need to normalize
	my @dot0= map $_->dot($vec0), @to_sort_cross;
	my @dot90= map $_->dot($vec90), @to_sort_cross;
	return $first, map $to_sort[$_], sort {
			($dot90[$a] >= 0? 1 - $dot0[$a] : 3 + $dot0[$a])
			<=>
			($dot90[$b] >= 0? 1 - $dot0[$b] : 3 + $dot0[$b])
		} 0..$#to_sort;
}

sub set_projection_origin {
	$_[0][5]= $_[0]->dot($_[1]);
	$_[0][3] ||= 0;
	$_[0][4] ||= 0;
	$_[0]
}
sub project {
	$_[0]->dot($_[1]) - ($_[0][5] || 0);
}

1;
