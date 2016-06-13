#! /usr/bin/env perl
use strict;
use warnings;
use File::Spec::Functions;
use FindBin;
use lib catdir($FindBin::Bin, '..', 'lib');
use Geo::SpatialDB::Import::OpenStreetMap;
use Geo::SpatialDB::Storage::LMDB_Storable;

my $db_path= shift or die "First argument must be tmp database";
my $input=   shift or die "Second argument must be OSM file";

my $importer= Geo::SpatialDB::Import::OpenStreetMap->new(
	tmp_storage => Geo::SpatialDB::Storage::LMDB_Storable->new(
		path => $db_path,
		run_with_scissors => 1,
	)
);

$importer->load_xml($input);
$importer->tmp_storage->commit;

my $stats= $importer->stats;
printf "Loaded %d nodes, %d ways, and %d relations\n", $stats->{node}, $stats->{way}, $stats->{relation};
