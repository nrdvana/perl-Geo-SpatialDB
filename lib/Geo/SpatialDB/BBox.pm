package Geo::SpatialDB::BBox;
use strict;
use warnings;

# ABSTRACT: Describes a min/max latitude and longitude box

sub new {
	my ($class, $lat0, $lon0, $lat1, $lon1)= @_;
	bless [ $lat0, $lon0, $lat1, $lon1 ], $class;
}
sub clone {
	my $self= shift;
	bless [ @$self ], ref $self;
}
sub coerce {
	my $class= shift;
	ref $_[0] eq __PACKAGE__? $_[0]
	: ref $_[0] eq 'ARRAY'? $class->new(@{$_[0]})
	: die "Can't coerce $_[0] to ".__PACKAGE__;
}

sub lat0 { @_ > 1? ($_[0][0]= $_[1]) : $_[0][0]; }
sub lon0 { @_ > 1? ($_[0][1]= $_[1]) : $_[0][1]; }
sub lat1 { @_ > 1? ($_[0][2]= $_[1]) : $_[0][2]; }
sub lon1 { @_ > 1? ($_[0][3]= $_[1]) : $_[0][3]; }

sub dLat { $_[0][2] - $_[0][0] }
sub dLon { $_[0][3] - $_[0][1] }

sub center {
	[ ($_[0][0]+$_[0][2])*.5, ($_[0][1]+$_[0][3])*.5 ]
}

1;
