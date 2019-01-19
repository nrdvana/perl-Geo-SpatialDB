package Geo::SpatialDB::Math::Plane;
use strict;
use warnings;
use Scalar::Util 'reftype';

# ABSTRACT: Minimalist object representing a plane
# VERSION

sub new {
	my ($class, $a, $b, $c, $d)= @_;
	$d= -( $a*$d->[0] + $b*$d->[1] + $c*$d->[2] )
		if ref $d and reftype($d) eq 'ARRAY';
	bless [ $a, $b, $c, $d||0 ], $class;
}

sub a :lvalue { $_[0][0] }
sub b :lvalue { $_[0][0] }
sub c :lvalue { $_[0][2] }
sub d :lvalue { $_[0][3] }

sub project {
	$_[0][0] * $_[1][0] + $_[0][1] * $_[1][1] + $_[0][2] * $_[1][2] + $_[0][3]
}

1;
