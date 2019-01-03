package Geo::SpatialDB::Math;
use strict;
use warnings;
use Exporter 'import';
use Math::Trig 'pi', 'pip2', 'spherical_to_cartesian';
our @EXPORT_OK= qw( latlon_rad_to_range latlon_to_xyz latlon_to_earth_xyz );
our %EXPORT_TAGS= ( 'all' => \@EXPORT_OK );

sub latlon_rad_to_range {
	my ($lat, $lon, $radius)= @_;
	my $dLat= $radius / 111000; # Latitude degrees are 111000m apart
	# Longitude is affected by latitude
	my $dLon= $radius / (111699 * cos($lat*pi / 180));
	return $lat-$dLat, $lon-$dLon, $lat+$dLat, $lon+$dLon;
}

sub latlon_to_xyz {
	return spherical_to_cartesian( 1, $_[0]*pi/180, pip2 - $_[1]*pi/180 );
}

sub latlon_to_earth_xyz {
	# TODO: handle the oblate spheroid thing
	return spherical_to_cartesian( 6_371_000, $_[0]*pi/180, pip2 - $_[1]*pi/180 );
}

1;
