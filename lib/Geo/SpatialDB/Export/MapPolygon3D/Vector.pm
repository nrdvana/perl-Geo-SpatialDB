package Geo::SpatialDB::Export::MapPolygon3D::Vector;
use strict;
use warnings;
use Carp 'croak';
use Exporter 'import';
our @EXPORT_OK= qw( vector );

sub new {
	my $class= shift;
	@_ >= 3 or croak "Require at least x,y,z arguments to Vector->new";
	bless [ @_ ], ref($class)||$class;
}
sub vector {
	__PACKAGE__->new(@_);
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
	my $scale= sqrt($_[0][0] * $_[0][0] + $_[0][1] * $_[0][1] + $_[0][2] * $_[0][2]);
	if ($scale) {
		$scale= 1/$scale;
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
