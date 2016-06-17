#! /usr/bin/env perl
use strict;
use warnings;
use File::Spec::Functions;
use FindBin;
use lib catdir($FindBin::Bin, '..', 'lib');
use Geo::SpatialDB;
use Geo::SpatialDB::Import::OpenStreetMap;
use Geo::SpatialDB::Storage::LMDB_Storable;
use Log::Any::Adapter 'Daemontools';

my $db_path= shift or die "First argument must be tmp database";
my $dest=   shift or die "Second argument must be the SpatialDB database";

my $importer= Geo::SpatialDB::Import::OpenStreetMap->new(
	tmp_storage => Geo::SpatialDB::Storage::LMDB_Storable->new(
		path => $db_path,
		run_with_scissors => 1,
	)
);

my $sdb= Geo::SpatialDB->new(
	storage => Geo::SpatialDB::Storage::LMDB_Storable->new(
		path => $dest,
	)
);

$importer->generate_roads($sdb);
$importer->tmp_storage->rollback; # it writes flags of which IDs were imported
$sdb->storage->commit;

my $stats= $importer->stats;
printf "Loaded %d roads with %d segments totaling %d verticies, with %d nodes\n",
	$stats->{gen_road}, $stats->{gen_road_seg}, $stats->{gen_road_seg_pts}, $stats->{gen_road_loc};
printf "By type:\n";
printf "   %10d  %s\n", $stats->{types}{$_}, $_
	for keys %{ $stats->{types} // {} };
