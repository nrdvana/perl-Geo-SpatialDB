#! /usr/bin/env perl
use strict;
use warnings;
use File::Spec::Functions;
use FindBin;
use lib catdir($FindBin::Bin, '..', 'lib');
use Geo::SpatialDB;
use Geo::SpatialDB::Import::OpenStreetMap;
use Geo::SpatialDB::Storage::LMDB_Storable;

my $sdb_path= shift or die "First argument must be database path";
my ($lat, $lon)= split ',', shift;
defined $lon or die "Second argument should be lat0,lon0";
#my ($lat1, $lon1)= split ',', shift;
#defined $lon1 or die "Third argument should be lat1,lon1";
my $rad= shift or die "Third argument is radius";

my $sdb= Geo::SpatialDB->new(
	storage => Geo::SpatialDB::Storage::LMDB_Storable->new(
		path => $sdb_path,
	)
);

$lat= int($lat * $sdb->latlon_precision)
	if $lat =~ /\./;
$lon= int($lon * $sdb->latlon_precision)
	if $lon =~ /\./;

my $result= $sdb->find_at($lat, $lon, $rad);
use JSON::XS;
my $j= JSON::XS->new->canonical->utf8->allow_blessed->convert_blessed;
while (my ($k, $v)= each %{ $result->{entities} }) {
	print "$k\t".$j->encode($v)."\n";
}
