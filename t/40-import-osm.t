use FindBin;
use lib "$FindBin::Bin/lib";
use TestGeoDB -setup => ':all';
use File::Spec::Functions;
use File::Path 'remove_tree','make_path';
use Log::Any::Adapter 'TAP';
use Geo::SpatialDB::Import::OpenStreetMap;

my $tmpdir= catdir($FindBin::RealBin, 'tmp', $FindBin::Script);
remove_tree($tmpdir, { error => \my $ignored });
make_path($tmpdir or die "Can't create $tmpdir");

my $importer= Geo::SpatialDB::Import::OpenStreetMap->new(
	tmp_storage => { mapsize => 10*1024*1024 },  # for cpan testers restrictions
);

package Test::Mock::SpatialDB {
	use Moo 2;
	use Log::Any '$log';
	use Geo::SpatialDB::Storage::Memory;
	
	has storage        => is => 'rw', default => sub { Geo::SpatialDB::Storage::Memory->new() };
	has location_count => is => 'rw', default => sub { 0 };
	has route_count    => is => 'rw', default => sub { 0 };
	has segment_count  => is => 'rw', default => sub { 0 };
	
	sub add_entity {
		my ($self, $entity)= @_;
		$log->debugf("%s", $entity);
		$self->{location_count}++ if $entity->isa('Geo::SpatialDB::Entity::Location');
		$self->{segment_count}++  if $entity->isa('Geo::SpatialDB::Entity::RouteSegment');
		$self->{route_count}++    if $entity->isa('Geo::SpatialDB::Entity::Route');
		$self->storage->put(entity => $entity->id, $entity);
	}
};

$importer->load_xml(catfile($FindBin::RealBin, 'data', 'peterborough.osm.bz2'));
$importer->tmp_storage->commit;

$importer->preprocess;
$importer->tmp_storage->commit;

my $sdb= Test::Mock::SpatialDB->new;
$importer->generate_roads($sdb);

is( $sdb->location_count, 448, 'locations' );
is( $sdb->segment_count,  553, 'route segments' );
is( $sdb->route_count,    238, 'routes' );

done_testing;
