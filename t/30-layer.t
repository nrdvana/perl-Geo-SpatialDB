#! /usr/bin/env perl
use Test2::V0;
use Geo::SpatialDB::Layer;

is( Geo::SpatialDB::Layer->new(code => 'layer1', mapper => { CLASS => 'Rect', lat_divs => 360, lon_divs => 90 }),
	object {
		call index_name => match qr/layer1/;
		call name => match qr/layer1/;
		call mapper => object { call [ tile_polygon => 0 ] => E(); };
		call min_feature_size => undef;
		call max_feature_size => undef;
		call type_filters => undef;
		call type_filter_regex => undef;
	},
	'Minimally configured layer' );

done_testing;
