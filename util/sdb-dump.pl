#! /usr/bin/env perl
use strict;
use warnings;
use File::Spec::Functions;
use FindBin;
use lib catdir($FindBin::Bin, '..', 'lib');
use JSON::XS;
use Geo::SpatialDB;
use Geo::SpatialDB::Import::OpenStreetMap;
use Geo::SpatialDB::Storage::LMDB_Storable;

my $sdb_path= shift or die "First argument must be database path";
my $key= shift;

my $sdb= Geo::SpatialDB->new(
	storage => Geo::SpatialDB::Storage::LMDB_Storable->new(
		path => $sdb_path,
	)
);

my $j= JSON::XS->new->canonical->allow_blessed->convert_blessed;

if ($key) {
	my $x= $sdb->storage->get($key);
	printf "%s\n", $j->encode($x);
}
else {
	my $i= $sdb->storage->iterator();
	while (my ($k, $v)= $i->()) {
		printf "%s\t%s\n", $k, $j->encode($v);
	}
}
