use FindBin;
use lib "$FindBin::Bin/lib";
use TestGeoDB -setup => ':all';
use Geo::SpatialDB::Layer;
use Geo::SpatialDB::Entity::RouteSegment;

my $db= new_geodb_in_memory();

# No layers should exist yet
is( [ $db->layer_list ], [], 'starts with no layers' );
# create one
my $layer1= Geo::SpatialDB::Layer->new(
	code => 'layer1',
	mapper => { CLASS => 'Rect', lat_divs => 360, lon_divs => 90 }
);
# then add it
$db->add_layer($layer1);
is( [ $db->layer_list ], [ $layer1 ], 'layer1 added' );
# The index of layers should contain it now
is( $db->storage->get('layer', 'layer1'), $layer1, "layer1 stored correctly" );
# and the index of the layer should exist
ok( $db->storage->iterator($layer1->index_name), "layer's index was created" );

# Now add an entity.  It should get added to the layer
my $ent1= Geo::SpatialDB::Entity::RouteSegment->new(
	id => $db->alloc_entity_id,
	type => 'rt',
	tags => {},
	latlon_seq => [ (.000_001, .000_001), (.000_002, .000_002) ],
);

$db->add_entity($ent1);
# entity should be added to layer's index
my ($bucket_id, $bucket)= $db->storage->iterator($layer1->index_name)->();
is( $bucket, { ent => [ $ent1->id ] }, 'entity indexed with layer1' );

# Now, add another layer
my $layer2= Geo::SpatialDB::Layer->new(
	code => 'layer2',
	mapper => { CLASS => 'Rect', lat_divs => 360, lon_divs => 90 },
);
$layer2->type_filter_regex; # trigger lazy build so match comes out right
$db->add_layer($layer2);
is( $db->storage->get('layer', 'layer2'), $layer2, 'layer2 stored correctly' );
($bucket_id, $bucket)= $db->storage->iterator($layer2->index_name)->();
is( $bucket, { ent => [ $ent1->id ] }, 'entity indexed with layer2' );

done_testing;
