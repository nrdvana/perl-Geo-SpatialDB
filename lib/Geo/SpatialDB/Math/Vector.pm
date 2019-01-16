package Geo::SpatialDB::Math::Vector;
use strict;
use warnings;
use Carp 'croak';
use Exporter 'import';
use Math::Trig qw( spherical_to_cartesian pi );
our @EXPORT_OK= qw( vector vector_latlon );

# VERSION

=head1 SYNOPSIS

  my ($x,$y,$z)= vector(1,2,3)->cross(vector(3,2,1))->normalize->xyz;

=head1 DESCRIPTION

This class implements a basic mathematic 3-space vector, optimized for performance as much as
reasonable for Perl.  Most methods mutate the current vector rather than returning new vector
objects, with the notable exception of 'cross' which returns a new vector.

This class also allows for 's' and 't' coordinates, useful for textures, and holds another
component used as "D" in the plane equation of C<< A*X + B*Y + C*Z = D >>.

=head1 EXPORTED FUNCTIONS

=head2 vector

Alias for C<< $class->new(@_) >>

=head2 vector_latlon

Alias for C<< $class->vector_latlon(@_) >>

=cut

sub vector { __PACKAGE__->new(@_); }
sub vector_latlon { __PACKAGE__->new_latlon(@_); }

=head1 ATTRIBUTES

The following accessors return l-values, which you can assign values to.

  my $x= $vec->x;
  $vec->x= $value;

=over

=item x

=item y

=item z

=item s

=item t

=item u

=item v

=back

The following "attributes" are shortcuts to access multiple fields at once:

  my ($x, $y, $z)= $vec->xyz;
  ($vec->xyz) = (1, 2, 3);

=over

=item xyz

=item st

=item stuv

=item stxyz

There are also some setter functions which return the vector, for convenient chaining:

  $v1->set_st(0,1)->scale(...)->...

=over

=item set_xyz

=item set_st

=item set_xyzst

=cut

sub x     : lvalue { $_[0][0] }
sub y     : lvalue { $_[0][1] }
sub z     : lvalue { $_[0][2] }
sub xyz   : lvalue { @{$_[0]}[0..2] }
sub s     : lvalue { $_[0][3] }
sub t     : lvalue { $_[0][4] }
sub u     : lvalue { $_[0][5] }
sub v     : lvalue { $_[0][6] }
sub st    : lvalue { @{$_[0]}[3..4] }
sub stuv  : lvalue { @{$_[0]}[3..6] }
sub xyzst : lvalue { @{$_[0]}[0..4] }
sub stxyz : lvalue { @{$_[0]}[3,4,0,1,2] }

sub set_xyz   { @{$_[0]}[0..2]= @_[1..$#_]; $_[0] }
sub set_st    { @{$_[0]}[3..4]= @_[1..$#_]; $_[0] }
sub set_stuv  { @{$_[0]}[3..6]= @_[1..$#_]; $_[0] }
sub set_xyzst { @{$_[0]}[0..4]= @_[1..$#_]; $_[0] }

=head1 METHODS

=head2 new

  $class->new($x, $y); # z=0, s=undef, t=undef
  $class->new($x, $y, $z); #  s=undef, t=undef
  $class->new($x, $y, $z, $s, $t);

Return a new vector object composed of two or more components.  The 's' and 't' coordinates are
not part of the vector unless specified (but can be assigned later).  Z defaults to 0.

=head2 new_latlon

  $class->new_latlon($lat, $lon);

Return a new vector of length 1 created from the polar coordinates, in degrees.

=head2 clone

Return a copy of a vector

=cut

sub new {
	my ($class, @vec)= @_;
	@vec >= 2 or croak "Require at least x,y arguments to Vector->new";
	$vec[2] ||= 0;
	bless \@vec, ref($class)||$class;
}
sub new_latlon {
	@_ == 3 && !ref $_[1] or croak "usage: Vector->new_latlon(lat,lon)";
	my ($class, $lat, $lon)= @_;
	bless [ spherical_to_cartesian( 1, $lon*pi/180, (90-$lat)*pi/180 ) ], ref($class)||$class;
}

sub clone {
	bless [ @{$_[0]} ], ref $_[0];
}

=head2 scale

  $vec->scale(5)->...

Multiply every component of the vector by the given value, and return the vector.

=head2 add

  $vec1->add($vec2)->...

Add the components of $vec2 to this vector for each component of this vector which is defined.
X, Y, and Z are always defined, but S and T might not be.

=head2 sub

Subtract the components of $vec2 from this vector, in the manner described for L</add>.

=cut

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

=head2 dot

Return the dot product of the two vectors.

=head2 cross

Return a new vector which is the cross-product of this vector by the argument.

=head2 mag_sq

Return the sum-of-squares of the C<x,y,z> components of this vector.
(aka the dot product of the vector with itself, or the square of the magnitude).

=head2 mag

Magnitude of the vector.

=head2 distance

Calculate magnitude between difference of this vector and another, without modifying either.

=head2 normalize

Scale the vector by the inverse of its magnitude, resulting in a unit-length vector.

=cut

sub dot {
	$_[0][0] * $_[1][0] + $_[0][1] * $_[1][1] + $_[0][2] * $_[1][2];
}

sub cross {
	bless [
		$_[0][1]*$_[1][2] - $_[0][2]*$_[1][1],
		$_[0][2]*$_[1][0] - $_[0][0]*$_[1][2],
		$_[0][0]*$_[1][1] - $_[0][1]*$_[1][0],
	], ref $_[0];
}

sub mag_sq {
	$_[0][0] * $_[0][0] + $_[0][1] * $_[0][1] * $_[0][2] * $_[0][2];
}

sub mag {
	sqrt($_[0][0] * $_[0][0] + $_[0][1] * $_[0][1] + $_[0][2] * $_[0][2])
}
*magnitude= *mag;

sub distance {
	my $dx= $_[0][0] - $_[1][0];
	my $dy= $_[0][1] - $_[1][1];
	my $dz= $_[0][2] - $_[1][2];
	return sqrt($dx * $dx + $dy * $dy + $dz * $dz);
}

sub normalize {
	my $mag_sq= $_[0][0] * $_[0][0] + $_[0][1] * $_[0][1] + $_[0][2] * $_[0][2];
	if ($mag_sq && $mag_sq != 1) {
		my $scale= 1/sqrt($mag_sq);
		$_ *= $scale for @{ $_[0] };
	}
	$_[0]
}

=head2 sort_vectors_by_heading

  my @sorted= $pole_vector->sort_vectors_by_heading( @vectors );

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

=head2 project_onto

Project this vector onto a plane (or plane's normal)

=cut

sub project_onto { $_[1]->project($_[0]) }

=head2 reflect_across

Reflect a this vector across the normal of a plane (the first argument), modifying and
returning this vector.

=cut

sub reflect_across {
	$_[0]->add($_[1]->clone->scale(-2 * $_[1]->dot($_[0])));
}

=head2 project

Pretend this vector is the normal of a plane passing through the origin, and project another
vector onto this one.

This is basically just a dot product.  This allows vectors to be used interchangably with
planes for the common case of planes based at the origin.  This vector is assumed to be
unit-length, but this condition is not checked.

=cut

*project= *dot;

1;
