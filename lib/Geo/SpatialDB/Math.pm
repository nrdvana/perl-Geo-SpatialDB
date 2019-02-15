package Geo::SpatialDB::Math;
use strict;
use warnings;
use Exporter 'import';
use Math::Trig 'pi', 'pip2', 'spherical_to_cartesian';
use GIS::Distance;
use Geo::SpatialDB::Math::Vector qw( vector vector_latlon );
use Geo::SpatialDB::Math::Polygon qw( polygon );
use Geo::SpatialDB::Math::Plane;
use Geo::SpatialDB::Math::LLRad;
use Geo::SpatialDB::Math::LLBox;
our @EXPORT_OK= qw( earth_radius latlon_distance latlon_rad_to_dlat_dlon latlon_rad_to_range
	latlon_to_xyz latlon_to_earth_xyz
	vector vector_latlon polygon plane llrad llbox );
our %EXPORT_TAGS= ( 'all' => \@EXPORT_OK );

# VERSION

use constant earth_radius => 6_371_640;
use constant meters_per_degree => earth_radius * pi * 2 / 360;

our $gd;
sub latlon_distance { ($gd //= GIS::Distance->new)->distance(@_)->meters }

sub latlon_rad_to_dlat_dlon {
	my ($lat, $lon, $radius)= @_;
	return (
		$radius / meters_per_degree, # Latitude degrees are 111000m apart
		$radius / (meters_per_degree * abs(cos($lat * pi/180))) # Longitude is affected by latitude
	);
}

sub latlon_rad_to_range {
	my ($dLat, $dLon)= &latlon_rad_to_dlat_dlon;
	return ($_[0]-$dLat, $_[1]-$dLon, $_[0]+$dLat, $_[1]+$dLon);
}

sub latlon_to_xyz {
	return spherical_to_cartesian( 1, $_[0] * pi/180, (90 - $_[1]) * pi/180 );
}

sub latlon_to_earth_xyz {
	# TODO: handle the oblate spheroid thing
	return spherical_to_cartesian( earth_radius, $_[0] * pi/180, (90 - $_[1]) * pi/180 );
}

sub llrad { Geo::SpatialDB::Math::LLRad->new(@_) }
sub llbox { Geo::SpatialDB::Math::LLBox->new(@_) }
sub plane { Geo::SpatialDB::Math::Plane->new(@_) }

1;
