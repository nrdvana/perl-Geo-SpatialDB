package Geo::SpatialDB::Math::LLBox;
use strict;
use warnings;
use Geo::SpatialDB::Math 'latlon_distance';

# ABSTRACT: Describes a min/max latitude and longitude box
# VERSION

=head1 DESCRIPTION

This class is a simple wrapper around a min/max latitude and longitude, which describe an area
of the globe.

This class has mostly the same API as LLRad, and can be used interchangably with it in most
places in the Geo::SpatialDB API, allowing you to use the notation that causes the least
expensive calculations.

=cut

sub new {
	my ($class, $lat0, $lon0, $lat1, $lon1)= @_;
	bless [ $lat0, $lon0, $lat1, $lon1 ], $class;
}

sub lat0 :lvalue { $_[0][0] }
sub lon0 :lvalue { $_[0][1] }
sub lat1 :lvalue { $_[0][2] }
sub lon1 :lvalue { $_[0][3] }
sub lat { ($_[0][0]+$_[0][2])*.5 }
sub lon { ($_[0][1]+$_[0][3])*.5 }

sub dLat { $_[0][2] - $_[0][0] }
sub dLon { $_[0][3] - $_[0][1] }

sub radius {
	latlon_distance(@{$_[0]});
}

sub clone {
	my $self= shift;
	bless [ @$self ], ref $self;
}
sub clone_as_llbox { shift->clone; }
sub clone_as_llrad { Geo::SpatialDB::Math::LLRad->new($_[0]->lat, $_[0]->lon, $_[0]->radius) }
sub as_llbox { $_[0] }
sub as_llrad { shift->clone_as_llrad }

sub coerce {
	my $class= shift;
	ref $_[0] eq __PACKAGE__? $_[0]
	: ref $_[0] eq 'ARRAY'? $class->new(@{$_[0]})
	: ref($_[0])->can('clone_as_llbox')? $_[0]->clone_as_llbox
	: die "Can't coerce $_[0] to ".__PACKAGE__;
}

1;
