package Geo::SpatialDB::Math::LLRad;
use strict;
use warnings;
use Geo::SpatialDB::Math 'latlon_rad_to_dlat_dlon', 'latlon_rad_to_range';

# ABSTRACT: Describes an area by latitude, longitude, and radius

=head1 DESCRIPTION

This class is a simple wrapper around a latitude, longitude, and radius which describe an area
of the globe.

This class has mostly the same API as LLBox, and can be used interchangably with it in most
places in the Geo::SpatialDB API, allowing you to use the notation that causes the least
expensive calculations.

=cut

sub new {
	my $class= shift;
	bless [ @_ ], $class;
}

sub lat :lvalue { $_[0][0] }
sub lon :lvalue { $_[0][1] }
sub radius :lvalue { $_[0][2] }

sub dLat { (latlon_rad_to_dlat(@{$_[0]}))[0] }
sub dLon { (latlon_rad_to_dlat(@{$_[0]}))[1] }
sub lat0 { $_[0][0] - $_[0]->dLat }
sub lon0 { $_[0][1] - $_[0]->dLon }
sub lat1 { $_[0][0] + $_[0]->dLat }
sub lon1 { $_[0][1] + $_[0]->dLon }

sub clone {
	my $self= shift;
	bless [ @$self ], ref $self;
}
sub clone_as_llbox { Geo::SpatialDB::Math::LLBox->new(latlon_rad_to_range(@{$_[0]})) }
sub clone_as_llrad { shift->clone; }
sub as_llbox { shift->clone_as_llbox }
sub as_llrad { $_[0] }

sub coerce {
	my $class= shift;
	ref $_[0] eq __PACKAGE__? $_[0]
	: ref $_[0] eq 'ARRAY'? $class->new(@{$_[0]})
	: ref($_[0])->can('clone_as_llrad')? $_[0]->clone_as_llrad
	: die "Can't coerce $_[0] to ".__PACKAGE__;
}

1;
