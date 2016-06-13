#! /usr/bin/env perl
use strict;
use warnings;
use File::Spec::Functions;
use FindBin;
use lib catdir($FindBin::Bin, '..', 'lib');
use Geo::SpatialDB::Import::OpenStreetMap;
use Geo::SpatialDB::Storage::LMDB_Storable;

my $db_path= shift or die "First argument must be tmp database";

my $importer= Geo::SpatialDB::Import::OpenStreetMap->new(
	tmp_storage => Geo::SpatialDB::Storage::LMDB_Storable->new(
		path => $db_path,
		run_with_scissors => 1,
	)
);

$importer->preprocess;
$importer->tmp_storage->commit;

my $stats= $importer->stats;
printf "processed %d ways and %d relations, rewriting %d nodes and %d ways\n",
	$stats->{preproc_way}, $stats->{preproc_relation},
	$stats->{preproc_rewrite_node}, $stats->{preproc_rewrite_way};
