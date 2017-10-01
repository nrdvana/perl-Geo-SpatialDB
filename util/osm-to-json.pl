#! /usr/bin/env perl
use strict;
use warnings;
use lib "lib";
use Geo::SpatialDB;
use Geo::SpatialDB::Import::OpenStreetMap;
use JSON;
binmode ':utf8';
my $j= JSON->new->canonical;
my $i= Geo::SpatialDB::Import::OpenStreetMap->new();
for (keys %{ $i->way_cache }) {
	print $j->encode($i->construct_way($_))."\n";
}
